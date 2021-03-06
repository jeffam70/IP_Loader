{Program:       Warm Booter

 Version:       0.9.2

 Purpose:       During normal Propeller Application runtime this object can be activated to "warm boot" the Propeller with a
                different, embedded Propeller Application (called a SubApp within this object).  When this object launches
                the SubApp, the Propeller environment (cogs, Main RAM, etc.) is exactly like that of a normal cold boot using
                that SubApp as the main application.  

 Background:    Based on portions of the ROM-Resident Propeller 1 BootLoader written by Chip Gracey.

 Operation:     When desired, call Start and pass the address of the SubApp to reboot with.

                Warm Booter performs the following tasks:
                  1) Launches an assembly-based routine into a cog
                  2) Immediately terminates all other cogs; including the main application cog
                  3) Loads the SubApp from the designated EEPROM address to Main RAM (address 0)
                  4) Clears variable/stack space and builds initial Spin stack frame; like normal Propeller Application image
                  5) Validates SubApp via start-of-code and checksum, shutting down Propeller if deemed invalid
                  6) Set's clock mode as designated by SubApp
                  7) Launches Spin Interpreter into Cog 0 to run SubApp
                  8) Terminates warm booter cog

 Requirements:  * The SubApp must be EEPROM-resident for Warm Booter to function properly.
                * SubApp can start anywhere in EEPROM; it does not need to be long or word aligned.
                * SubApp must be a standard Propeller Application (code, followed by variables, followed by stack space).                
 
 }



{ DONE:
    * Terminate all other cogs before writing RAM.
    * Merge ee_write into ee_read since it won't be used any other way for purposes of this code.
    * Fix Clock Set routine to account for current clock mode.  Adjust Clock Settings according to Clock.spin
    * Finalize CalcDelay routine.
    * Calculate I2C delay factors.
    * Merge Shutdown into CheckValidity and Shutdown routines.
    * Insert I2C delays into I2C routines.
    * Build launching interface.
    * Tested and modified I2C routines.
    * Verified EEPROM loading.
    * Verified SubApp validity check and booter shutdown.
    * Possibly read 4 bytes of code at a time (into a long) from EEPROM and do one wrlong to RAM.
    * Validate code via Start of Code pointer and Checksum.
    * Clear all RAM beyond SubApp Code.
    * Insert initial Spin Stack Frame.
    * Trued-up I2C timing to meet exact specs (Clock 1.3 low / 0.6 high).
    * Removed necessity for SCLLowHalfTime.
    * Set minimum in CalcDelay to prevent slow main app clock speed causing I2C routines to miss a time window.
    * Adjusted minimum in CalcDelay for real I2C worst-case, which is rare.
    * Tested- works down to rcfast (12_000_000) and 5_000_000 (pll1x).  Does not work at rcslow for some unknown reason.
    * Enhanced some documentation.
    * Increased timeout for EE Ack on Start condition to be > 5 ms worst case (80 MHz & 1 MHz protocol speed)}


{ THINGS TO CONSIDER:
    * Make feature to warm boot from RAM rather than EEPROM.}    
 

VAR

  long  Addr                    {Persistant RAM to store SubApp address}
   
pub Start(SubAppAddr)
{{Launch warm booter into Cog 7, halt all other cogs, and warm boot Propeller with SubApp at SubAppAddr}}

  Addr := SubAppAddr            {Store full address of SubApp in persistent place}
  coginit(7, @WarmBoot, @Addr)  {Launch warm booter (passing pointer to SubApp)}


DAT
                        
{
 WarmBoot reinitializes Propeller cogs and memory, loads SubApp from EEPROM to Main RAM, and launches Spin Interpreter for
 SubApp (as if SubApp were cold-booted as a normal Propeller Application).

 Requirements:  PAR must be long-aligned Main RAM address that contains the EEPROM byte address of the SubApp to launch.
}                                                       
                        org
                            
WarmBoot                cogid   ID                      'Get cog ID
                        mov     Count, #7               'Set loop count                                 [Terminate all other cogs]
Terminate               add     ID, #1                  'Get next cog ID (only 3 LSBs matter)
                        cogstop ID                      'Stop cog 
                        djnz    Count, #Terminate       'Loop until we're all alone

                        mov     Y, STime                'Get I2C Start/Stop time factor                 [Determine required timing]
                        call    #CalcDelay              'Convert to clock cycles and store
                        mov     STime, R                
                        mov     Y, SCLHighTime          'Get I2C SCL High time factor                   
                        call    #CalcDelay              'Convert to clock cycles and store
                        mov     SCLHighTime, R          
                        mov     Y, SCLLowTime           'Get I2C SCL Low time factor                    
                        call    #CalcDelay              'Convert to clock cycles and store
                        mov     SCLLowTime, R           
                        mov     Y, PLLSettleTime        'Get system PLL settle delay factor             
                        call    #CalcDelay              'Convert to clock cycles
                        shr     R, #2                   'Divide by 4 to equal inst. cycles                                    

                        rdbyte  CMode, #$0004           'Read current ClockMode                         [Save current ClockMode for later]

                        call    #EE_StartRead           'Send read command                              [Load SubApp code from EEPROM to RAM]
                        mov     Count, #2               'Load 1st 2 longs of SubApp initialization 
                        call    #GetSubAppImage         'stream to RAM
                        shr     LongVal, #16            'Validate start of Spin code
                        cmp     LongVal, #$10   wz      'z = valid, nz = invalid
        if_nz           jmp     #Shutdown               'If invalid application; shutdown Propeller
                        mov     Count, #1               'Load next long of SubApp initialization
                        call    #GetSubAppImage         'stream to RAM
                        mov     StackAddr, LongVal      'Save Spin Stack address for later
                        shr     StackAddr, #16          
                        mov     Count, LongVal          'Find SubApp code size; Start Of Variables (SOV)
                        and     Count, WordMask         'Isolate SOV
                        shr     Count, #2               'Convert to long count
                        sub     Count, #3               'Adjust for longs already read
                        call    #GetSubAppImage         'Load remaining longs of SubApp code to RAM   
                        call    #EE_Stop                'End EEPROM read
                        and     CSum, #$FF              'Validate SubApp checksum
                        tjnz    CSum, #Shutdown         'If invalid application; shutdown Propeller

                        neg     Count, RAMAddr          'Get negative of current RAM address            [Clear remaining RAM]
                        sar     Count, #2               'Divide by 4; convert to negative longs
                        add     Count, RAMSize          'Count = -longs + RAMSize = remaining longs
                        mov     LongVal, #0             'Prepare long value (0)
:ClearRAM               wrlong  LongVal, RAMAddr        'Clear long at RAMAddr
                        add     RAMAddr, #4             'Increment RAMAddr
                        djnz    Count, #:ClearRAM       'Loop until end of memory

                        sub     StackAddr, #8           'Adjust Stack Address for initial stack frame   [Write initial stack frame]
                        wrlong  InitStack, StackAddr
                        add     StackAddr, #4
                        wrlong  InitStack, StackAddr

                        rdbyte  Temp, #$0004            'Read new ClockMode                             [Set clock as requested]
                        test    Temp, #$20      wz      'Does new mode enable ext osc? nz = yes
        if_nz           cmp     CMode, #$20     wc      '  If so, does current mode have ext. osc disabled? c = yes
        if_nz_and_c     and     CMode, #$07             '    If so, preserve current clock source,
        if_nz_and_c     and     Temp, #$78              '      ignore new clock source,
        if_nz_and_c     or      CMode, Temp             '      and merge the two modes together, then
        if_nz_and_c     clkset  CMode                   '      activate new PLL, OSC, and gain settings
:Settle if_nz_and_c     djnz    R, #:Settle             '      and wait for crystal and PLL to settle
        if_nz_and_c     rdbyte  Temp, #$0004            '      then ready new ClockMode (with new clock source)
                        clkset  Temp                    'Set clock to new mode (PLL, OSC, gain, and source)

                        coginit Interpreter             'Load Cog 0 with interpreter                    [Launch Spin Interpreter]
                        
                        add     ID, #1                  'If we're here, we are not Cog 0; determine ID  [Terminate self if not Cog 0]
                        cogstop ID                      'and stop ourself

{***************************************
 *             Subroutines             *
 ***************************************}

{Get SubApp code image from EEPROM and store in Main RAM.
 Requirements:  Count must be number of longs of EEPROM to load.
                EE_StartRead must be called before first call here.
                EE_Stop should be called after last call here.}
GetSubAppImage          mov     LongVal, #0             'Clear long value                               [Read long(s) from EEPROM, write to RAM]
                        mov     Bytes, #4               'Prep for 4 bytes
:NextByte               call    #EE_Receive             'Get EEPROM byte
                        add     CSum, EEData            'Calculate Checksum
                        or      LongVal, EEData         'Insert new byte
                        ror     LongVal, #8             'Rotate new value into position
                        djnz    Bytes, #:NextByte       'Loop if more bytes
                        wrlong  LongVal, RAMAddr        'Write long to RAM
                        add     RAMAddr, #4             'Inc RAM address
                        djnz    Count, #GetSubAppImage  'Loop until Count longs read/written
GetSubAppImage_ret      ret                             'Return
                        
'***************************************

{Calculate delay by dividing current clock speed (X) by delay factor (Y). Returns 32-bit integer result in R.
 Requirements:  Y must contain desired delay factor.}
CalcDelay               rdlong  X, #$0000               'Read current clock speed (LONG[0])             [Calculate Delay; X ÷ Y  clock speed ÷ delay factor]
                        mov     R, #0           wz      'Clear result (quotient); z = 1
                        mov     Count, #0               'Clear Y indention count
                        cmp     X, Y            wc      'Check dividend and divisor; c = dividend < divisor
              if_b      jmp     #CalcDelay_ret          'Dividend (X) < divisor (Y)?  Exit
:Justify      if_z      rol     X, #1                   'X not justified? Rotate X left                 
                        test    X, #1           wz      'Test X[0]; nz = X wrapped around (X[0] is 1)
                        rol     Y, #1           wc      'Rotate Y left; c = Y wrapped around (Y[0] is 1)
              if_nz     add     Count, #1               'If X justified, increment Y's indention count         
              if_nc     jmp     #:Justify               'Y not justified? Loop; also justifies X if X > Y
                        ror     X, #1                   'Rotate X's and Y's highest 1 bit back to bit 31
                        ror     Y, #1                   
:Div                    cmpsub  X, Y            wc      'X >= Y? Subtract Y; c = quotient bit
                        rcl     R, #1                   'Rotate c into quotient (result)
                        ror     Y, #1                   'Rotate divisor
                        djnz    Count, #:Div            'Loop until done; Y indention count clear
                        min     R, #30                  'Limit minimum to I2C routine's worst-case 
CalcDelay_ret           ret                             'Return; 32-bit integer result in R.

'***************************************

{Shutdown EEPROM and Propeller}
Shutdown                call    #EE_Shutdown            'Shutdown EEPROM and I/O
                        clkset  ClkFreeze               'Stop clock; suspend Propeller until reset

'***************************************
'* I2C routines for 24xC256/512 EEPROM *
'***************************************
{Start Read Sequential EEPROM operation}
EE_StartRead            mov     EEAddr, par             'Get pointer to SubApp pointer                  [Start EEPROM Read]
                        rdlong  EEAddr, EEAddr          'Get SubApp pointer
                        mov     Count, #511             '>5ms of EE Ack attempts @80MHz (1MHz protocol)
:Loop                   mov     EEData, #$A0            'Send write command
                        call    #EE_Start               
              if_c      djnz    Count, #:Loop           'No ack?  Loop until exhausted attempts
              if_c      jmp     #Shutdown               'No ack and exhausted?  Shutdown Propeller
                        mov     EEData, EEAddr          'Send EEPROM high address
                        shr     EEData, #8
                        call    #EE_Transmit
              if_c      jmp     #Shutdown               'No ack?  Shutdown Propeller
                        mov     EEData, EEAddr          'Send EEPROM low address
                        call    #EE_Transmit
              if_c      jmp     #Shutdown               'No ack?  Shutdown Propeller
                        mov     EEData, #$A1            'Send read command
                        call    #EE_Start
              if_c      jmp     #Shutdown               'No ack?  Shutdown Propeller
EE_StartRead_ret        ret

'***************************************
{Start EEPROM operation and transmit command (in EEData)}
EE_Start                mov     Bits, #9                'Ready 9 start attempts                         [Start EEPROM (and Transmit)]
                        mov     Delay, SCLLowTime       'Prep for SCL Low time
                        add     Delay, cnt
:Loop                   andn    outa, Mask_SCL          'Ready SCL low
                        or      dira, Mask_SCL          'SCL low
                        nop                             'Tiny delay
                        andn    dira, Mask_SDA          'SDA float
                        waitcnt Delay, STime            'Wait SCL Low time and prep for Start Setup time
                        or      outa, Mask_SCL          'SCL high
                        waitcnt Delay, STime            'Wait Start Setup time and prep for Start Hold time
                        test    Mask_SDA, ina   wc      'Sample SDA
              if_nc     djnz    Bits, #:Loop            'SDA not high?  Loop until exhausted attempts
              if_nc     jmp     #Shutdown               'SDA still not high?  Shutdown Propeller
                        or      dira, Mask_SDA          'SDA low  (Start Condition)
                        waitcnt Delay, #0               'Wait Start Hold time (no prep for next delay)
                        
'***************************************
{Transmit to or Receive from EEPROM}
EE_Transmit             shl     EEData, #1              'Ready to transmit byte and receive ack  [Transmit/Receive]
                        or      EEData, #%00000000_1    
                        jmp     #EE_TxRx                
EE_Receive              mov     EEData, #%11111111_0    'Ready to receive byte and transmit ack
EE_TxRx                 mov     Bits, #9                'Set for 9 bits (8 data + 1 ack (if Tx))
                        mov     Delay, SCLLowTime       'Prep for SCL Low time
                        add     Delay, cnt
:Loop                   andn    outa, Mask_SCL          'SCL low
                        test    EEData, #$100   wz      'Get next SDA output state
                        rcl     EEData, #1              'Shift in prior SDA input state
                        muxz    dira, Mask_SDA          'Generate SDA state (SDA low/float)
                        waitcnt Delay, SCLHighTime      'Wait SCL Low time and prep for SCL High time
                        test    Mask_SDA, ina   wc      'Sample SDA
                        or      outa, Mask_SCL          'SCL high
                        waitcnt Delay, SCLLowTime       'Wait SCL High time and prep for SCL Low time
                        djnz    Bits, #:Loop            'If another bit, loop
                        and     EEData, #$FF            'Isolate byte received
EE_Receive_ret
EE_Transmit_ret
EE_Start_ret            ret                             'nc = ack

'***************************************
{Stop EEPROM operation}
EE_Stop                 mov     Bits, #9                'Ready 9 stop attempts                          [Stop]
:Loop                   andn    outa, Mask_SCL          'SCL low
                        mov     Delay, cnt
                        add     Delay, SCLLowTime       'Prep for SCL low time
                        or      dira, Mask_SDA          'SDA low
                        waitcnt Delay, STime            'Wait SCL Low time and prep for Stop setup time
                        or      outa, Mask_SCL          'SCL high
                        waitcnt Delay, SCLHighTime      'Wait Stop setup time and prep for SCL High time
                        andn    dira, Mask_SDA          'SDA float  (Stop Condition)
                        waitcnt Delay, #0               'Wait SCL High time (no prep for next delay)
                        test    Mask_SDA,ina    wc      'Sample SDA
              if_nc     djnz    Bits, #:Loop            'If SDA not high, loop until done
EE_Jmp        if_nc     jmp     #Shutdown               'If SDA still not high, shutdown

EE_Stop_ret             ret                             

'***************************************
{Shutdown EEPROM and Propeller pin outputs}
EE_Shutdown             mov     EE_Jmp, #0              'Deselect EEPROM (replace jmp with nop)         [Shutdown EEPROM]
                        call    #EE_Stop                '(always returns)
                        mov     dira, #0                'Cancel any outputs
EE_Shutdown_ret         ret                             'Return

'***************************************
'*       Constants and Variables       *
'***************************************

{Constants}
Mask_SDA                long    %1 << 29                                        'Pin mask for EEPROM's SDA pin (P29)
Mask_SCL                long    %1 << 28                                        'Pin mask for EEPROM's SCL pin (P28)
RAMSize                 long    8192                                            'RAM Size (in longs)
InitStack               long    $FFF9FFFF                                       'Initial Stack Frame value
ClkFreeze               long    $02                                             'Setting to stop clock; XINPUT mode plus oscillator feedback disabled
Interpreter             long    $0001 << 18 + $3C01 << 4 + %0000                'Spin Interpreter startup settings
WordMask                long    $FFFF                                           'Mask for lower word of long

{Timing Delays
 These are constant factors which get converted to clock cycles at run-time.
 With floating-point math, the clock cycles per time factor would be calculated as clock_frequency × time_factor:
      Ex:  80_000_000 × 0.000_000_6 = 48
 Since floating-point isn't naturally supported in Propeller Assembly, the time factors are instead entered as reciprocals
 (multiplicative inverses) so those constants can be integers with reasonable accuracy, then we divide instead of multiply,
 making the equation clock_frequency ÷ time_factor:
    Ex:  80_000_000 ÷ (1 / 0.000_000_6)  80_000_000 ÷ 1_666_666 = 48}
PLLSettleTime           long    trunc(1.0 / 0.010)                              'Xtal/PLL settle frequency (1/10 ms)
STime                   long    trunc(1.0 / 0.000_000_6)                        'Minimum Start/Stop Condition setup/hold time (1/0.6 µs)
SCLHighTime             long    trunc(1.0 / 0.000_000_6)                        'Minimum SCL high time frequency (1/0.6 µs)
SCLLowTime              long    trunc(1.0 / 0.000_001_3)                        'Minimum SCL low time frequency (1/1.3 µs)
      
{Initialized Variables}
RAMAddr                 long    0
CSum                    long    $7EC                                            'Checksum result (initialized to include initial stack frame)

{Uninitialized Variables}
ID                      res     1                                               'Holds this cog's ID
Count                   res     1                                               'General purpose counter
Bits                    res     1                                               'Bits counter for I2C
Bytes                   res     1                                               'Byte counter for GetSubAppImage routine
Delay                   res     1                                               'End of delay time window
Temp                                                                            'Temporary storage
EEData                  res     1                                               'EEPROM data temporary storage
EEAddr                  res     1                                               'EEPROM address
LongVal                 res     1                                               'Long value; 4 bytes of EEPROM data
CMode                   res     1                                               'Clock mode value
X                       res     1                                               'Dividend of CalcDelay routine
Y                       res     1                                               'Divisor of CalcDelay routine
R                       res     1                                               'Result (quotient) of CalcDelay routine
StackAddr               res     1                                               'Address of the Start of Spin Stack


{EEPROM Timing:

The I2C routines (above) conform to the EEPROM specs (below) with respect to the standard Propeller-to-EEPROM circuit.
Only three "settable" timing factors are needed by these routines (defined in the Timing Delays section, above):

  1) STime - The minimum Start/Stop Condition setup/hold time; a combination of timing specs #5, #6, and #9.
  2) SCLHighTime - The minimum SCL High time; timing spec #3.
  3) SCLLowTime - The minimum SCL Low time; timing spec #4.

All other timing factors are automatically accounted for in the design of the I2C routines combined with the circuit.

┌─────────────────────────────────────────────────┐ ┌───────────────────────────────────────────────────────────────────────────┐ 
│     24xC256I / 24xC512I EEPROM Timing Chart     │ │             24xC256I / 24xC512I  EEPROM Timing Specifications             │ 
├─────────────────────────────────────────────────┤ ├──────────────────────────────────┬───────────────────┬┬───────────────────┤ 
│                                                 │ │                                  │  3.3 v / 400 KHz  ││   3.3 v / 1 MHz   │
│          1  2  ├ 3 ┼ 4 ┤                      │ │                                  │                   ││                   │ 
│ SCL     ... │ │   Event Item and Description     │   Min      Max    ││   Min      Max    │ 
│          │5│6│       │7│8│           │9├ A ┤    │ ├──────────────────────────────────┼─────────┼─────────┼┼─────────┼─────────┤ 
│ SDA IN  ... │ │1 - SCL and SDA Rise Time ¹       │         │ 0.30 µs ││         │ 0.30 µs │ 
│                              │B│                │ ├──────────────────────────────────┼─────────┼─────────┼┼─────────┼─────────┤ 
│ SDA OUT ...            │ │2 - SCL and SDA Fall Time ¹       │         │ 0.30 µs ││         │ 0.10 µs │ 
│                                                 │ ├──────────────────────────────────┼─────────┼─────────┼┼─────────┼─────────┤ 
└─────────────────────────────────────────────────┘ │3 - SCL High Period               │ 0.60 µs │         ││ 0.50 µs │         │ 
                                                    ├──────────────────────────────────┼─────────┼─────────┼┼─────────┼─────────┤
                                                    │4 - SCL Low Period                │ 1.30 µs │         ││ 0.50 µs │         │
                                                    ├──────────────────────────────────┼─────────┼─────────┼┼─────────┼─────────┤
                                                    │5 - Start-Condition Setup Time    │ 0.60 µs │         ││ 0.25 µs │         │
                                                    ├──────────────────────────────────┼─────────┼─────────┼┼─────────┼─────────┤
                                                    │6 - Start-Condition Hold Time     │ 0.60 µs │         ││ 0.25 µs │         │
                                                    ├──────────────────────────────────┼─────────┼─────────┼┼─────────┼─────────┤
                                                    │7 - Data Hold Time                │  0 µs ² │         ││  0 µs ² │         │
                                                    ├──────────────────────────────────┼─────────┼─────────┼┼─────────┼─────────┤
                                                    │8 - Data Setup Time               │ 0.10 µs │         ││ 0.10 µs │         │
                                                    ├──────────────────────────────────┼─────────┼─────────┼┼─────────┼─────────┤
                                                    │9 - Stop-Condition Setup Time     │ 0.60 µs │         ││ 0.25 µs │         │
                                                    ├──────────────────────────────────┼─────────┼─────────┼┼─────────┼─────────┤
                                                    │A - Time Between Stop/Start-Cond's│ 1.30 µs │         ││ 0.50 µs │         │
                                                    ├──────────────────────────────────┼─────────┼─────────┼┼─────────┼─────────┤
                                                    │B - SCL low to SDA Data Out       │         │ 0.90 µs ││         │ 0.40 µs │
                                                    └──────────────────────────────────┴─────────┴─────────┴┴─────────┴─────────┘
                                                    ¹ Accomplished purely by circuity.                                           
                                                    ² Is at least as wide as #2 to bridge undefined region of falling SCL.        
                                                    
}
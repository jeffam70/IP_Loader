{This was used in the development of the EEPROM programming and verifying routines to be added to the end of the IP_Loader.spin code.}

{To-Do: Write acknowledge/non-acknowledge routines.
}
{Done: Writes entire RAM in page-mode (64-bytes at a time).
       Write verify routine.
       Verify timing at 80 MHz.
       Determine if any timing/code improvements can be made.
         Improved EE_Start routine to more closely follow the minimum specs.
       Verified timing at 80, 40, 20, and 10 MHz.  Adjusted code slightly to lower minimum STime.  Determined minimum cycles for timing factors.
       Determine if nops are really needed... it doesn't seem possible for two signals to be too close to each other at this speed.
}

{
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│   Min and Max Specifications for Microchip 24xx256/512 EEPROM @ 2.5 V <= Vcc <= 5.5V.    │
│                                                                                          │
│                              1  2  ├ 3 ┼ 4 ┤                                           │
│                     SCL     ...                      │
│                              │5│6│       │7│8│           │9├ A ┤                         │
│                     SDA IN  ...                      │
│                                                  │B│                                     │
│                     SDA OUT ...                                 │
├──────────────────────────────────┬─────────────────┬┬─────────────────┬┬─────────────────┤
│                                  │  100 KHz Speed  ││  400 KHz Speed  ││   1 MHz Speed   │
│   Event Item and Description     │  Min      Max   ││  Min      Max   ││  Min      Max   │
├──────────────────────────────────┼────────┼────────┼┼────────┼────────┼┼────────┼────────┤
│1 (SCL and SDA Rise Time)         │        │ 1.00 µs││        │ 0.30 µs││        │ 0.30 µs│
├──────────────────────────────────┼────────┼────────┼┼────────┼────────┼┼────────┼────────┤
│2 (SCL and SDA Fall Time)         │        │ 0.30 µs││        │ 0.30 µs││        │ 0.10 µs│
├──────────────────────────────────┼────────┼────────┼┼────────┼────────┼┼────────┼────────┤
│3 (SCL High Period)               │ 4.0 µs │        ││ 0.6 µs │        ││ 0.5 µs │        │
├──────────────────────────────────┼────────┼────────┼┼────────┼────────┼┼────────┼────────┤
│4 (SCL Low Period)                │ 4.7 µs │        ││ 1.3 µs │        ││ 0.5 µs │        │
├──────────────────────────────────┼────────┼────────┼┼────────┼────────┼┼────────┼────────┤
│5 (Start-Condition Setup Time)    │ 4.7 µs │        ││ 0.6 µs │        ││ 0.25 µs│        │
├──────────────────────────────────┼────────┼────────┼┼────────┼────────┼┼────────┼────────┤
│6 (Start-Condition Hold Time)     │ 4.0 µs │        ││ 0.6 µs │        ││ 0.25 µs│        │
├──────────────────────────────────┼────────┼────────┼┼────────┼────────┼┼────────┼────────┤
│7 (Data Hold Time)                │  0 µs  │        ││  0 µs  │        ││  0 µs  │        │
├──────────────────────────────────┼────────┼────────┼┼────────┼────────┼┼────────┼────────┤
│8 (Data Setup Time)               │ 0.25 µs│        ││ 0.1 µs │        ││ 0.1 µs │        │
├──────────────────────────────────┼────────┼────────┼┼────────┼────────┼┼────────┼────────┤
│9 (Stop-Condition Setup Time)     │ 4.0 µs │        ││ 0.6 µs │        ││ 0.25 µs│        │
├──────────────────────────────────┼────────┼────────┼┼────────┼────────┼┼────────┼────────┤
│A (Time Between Stop/Start-Cond's)│ 4.7 µs │        ││ 1.3 µs │        ││ 0.5 µs │        │
├──────────────────────────────────┼────────┼────────┼┼────────┼────────┼┼────────┼────────┤
│B (SCL low to SDA Data Out)       │        │ 3.5 µs ││        │ 0.9 µs ││        │ 0.4 µs │
└──────────────────────────────────┴────────┴────────┴┴────────┴────────┴┴────────┴────────┘
}       

CON               
        _clkmode = xtal1 + pll16x                                               'Standard clock mode * crystal frequency = 80 MHz
        _xinfreq = 5_000_000

  MaxPayload     = 1392                                                         'Maximum size of packet payload (in bytes)

PUB Main             

  cognew(@EEPROMProgramVerify, 0)

DAT
  {RAM programed and verified; Program EEPROM}                 
  EEPROMProgramVerify       mov     MemAddr, #$0            

                            {MemAddr = $0000}
                            {Program EEPROM}
    :NextPage               call    #EE_StartWrite                              'Begin sequential (page) write
                            mov     Bytes, #$40                                 '  Ready for $40 bytes (per page)
    :NextByte               rdbyte  SByte, MemAddr                              '    Get next RAM byte
                            call    #EE_Transmit                                '      Send byte
                if_c        jmp     #EEFail                                     '      Error? Abort
                            add     MemAddr, #1                                 '      Increment address
                            djnz    Bytes, #:NextByte                           '    Loop for full page
                            call    #EE_Stop                                    '  Initiate page-program cycle
                            cmp     MemAddr, EndOfRAM       wz                  '  Copied all RAM? z=yes
                if_nz       jmp     #:NextPage                                  'Loop until copied all RAM

                            {Verify EEPROM}
                            mov     MemAddr, #$0                                'Reset address
                            mov     Bytes, EndOfRAM                             'Ready for all bytes (full memory)
                            call    #EE_StartRead                               'Begin sequential read
    :CheckNextByte          call    #EE_Receive                                 '  Get next EEPROM byte (into SByte)
                            rdbyte  Bits, MemAddr                               '  Get next RAM byte (into Bits)
                            cmp     Bits, SByte             wz                  '  Are they the same? (z = yes)
                if_nz       jmp     #EEFail                                     '  If not equal, abort
                            add     MemAddr, #1                                 '  Increment address
                            djnz    Bytes, #:CheckNextByte                      'Loop for all bytes

                            {Done}
                            call    #EE_Stop                                    'Disengage EEPROM
                
  EEFail                    jmp     #$
                                               

'***************************************
'* I2C routines for 24xx256/512 EEPROM *
'***************************************
{Start Sequential Read EEPROM operation.
 Caller need not honor page size.}
  EE_StartRead              call    #EE_StartWrite                              'Start write operation (to send address)        [Start EEPROM Read]
                            mov     SByte, #$A1                                 'Send read command
                            call    #EE_Start
                if_c        jmp     #EEFail                                     'No ACK?  Abort
  EE_StartRead_ret          ret

'***************************************
{Start Sequential Write EEPROM operation.
 Caller must honor page size by calling EE_Stop
 before overflow.}                                          
  EE_StartWrite             mov     Longs, #511                                 '>11ms of EE Ack attempts @80MHz                [Wake EEPROM, Start EEPROM Write]
    :Loop                   mov     SByte, #$A0                                 'Send write command
                            call    #EE_Start
                if_c        djnz    Longs, #:Loop                               'No ACK?  Loop until exhausted attempts
                if_c        jmp     #EEFail                                     'No ACK and exhausted?  Abort
                            mov     SByte, MemAddr                              'Send EEPROM high address
                            shr     SByte, #8
                            call    #EE_Transmit
                if_c        jmp     #EEFail                                     'No ACK?  Abort
                            mov     SByte, MemAddr                              'Send EEPROM low address
                            call    #EE_Transmit
                if_c        jmp     #EEFail                                     'No ACK?  Abort
  EE_StartWrite_ret         ret


'***************************************
{Start EEPROM operation and transmit command (in SByte).}
  EE_Start                  mov     Bits, #9                                    'Ready 9 "Start" attempts                       [Start EEPROM (and Transmit)]
    :Loop                   mov     BitDelay, SCLLowTime                        'Prep for SCL Low time
                            add     BitDelay, cnt                               '
                            andn    outa, SCLPin                    '4          '  Ready SCL low
                            or      dira, SCLPin                    '4          '  SCL low
                            andn    dira, SDAPin                    '4          '  SDA float
                            waitcnt BitDelay, STime                 '6+(18+)    '  Wait SCL Low time and prep for Start Setup time
                            or      outa, SCLPin                    '4          '  SCL high
                            test    SDAPin, ina             wc      '4          '  Sample SDA; c = ready, nc = not ready
                            waitcnt BitDelay, STime                 '6+(14+)    '  Wait Start Setup time and prep for Start Hold time
                if_c        or      dira, SDAPin                    '4          '  If buss free, set SDA low (Start Condition)
                if_c        waitcnt BitDelay, #0                    '6+(10+)    '  If buss free, wait Start Hold time (no prep for next delay)
                if_nc       djnz    Bits, #:Loop                                'If buss busy, loop until exhausted attempts
                if_nc       jmp     #EEFail                                     'Buss busy and exhausted attempts? Abort
                        
'***************************************
{Transmit to or receive from EEPROM.
 On return: c = NAK, nc = ACK.}
  EE_Transmit               shl     SByte, #1                                   'Ready to transmit byte and receive ACK         [Transmit/Receive]
                            or      SByte, #%00000000_1                          
                            jmp     #EE_TxRx                                     
  EE_Receive                mov     SByte, #%11111111_0                         'Ready to receive byte and transmit ACK
  EE_TxRx                   mov     Bits, #9                                    'Set for 9 bits (8 data + 1 ACK (if Tx))
                            mov     BitDelay, SCLLowTime                        'Prep for SCL Low time
                            add     BitDelay, cnt                                
    :Loop                   andn    outa, SCLPin                    '4          'SCL low
                            test    SByte, #$100            wz      '4          '  Get next SDA output state; z=bit
                            rcl     SByte, #1                       '4          '  Shift in prior SDA input state
                            muxz    dira, SDAPin                    '4          '  Generate SDA state (SDA low/float)
                            waitcnt BitDelay, SCLHighTime           '6+(22+)[26]' Wait SCL Low time and prep for SCL High time
                            test    SDAPin, ina             wc      '4          '  Sample SDA
                            or      outa, SCLPin                    '4          '  SCL high
                            waitcnt BitDelay, SCLLowTime            '6+(14+)    '  Wait SCL High time and prep for SCL Low time
                            djnz    Bits, #:Loop                    '4          'If another bit, loop
                            and     SByte, #$FF                                 'Isolate byte received
  EE_Receive_ret
  EE_Transmit_ret
  EE_Start_ret              ret                                                 'nc = ACK

'***************************************
{Stop EEPROM operation.
 EE_StartRead/EE_StartWrite must have been called prior.}
  EE_Stop                   mov     Bits, #9                                    'Ready 9 stop attempts                          [Stop]
    :Loop                   andn    outa, SCLPin                                'SCL low
                            mov     BitDelay, cnt                               '  Prep for SCL low time
                            add     BitDelay, SCLLowTime            '4          
                            or      dira, SDAPin                    '4          '  SDA low
                            waitcnt BitDelay, STime                 '6+[14+]    '  Wait SCL Low time and prep for Stop setup time
                            or      outa, SCLPin                    '4          '  SCL high
                            waitcnt BitDelay, SCLHighTime           '6+[10+]    '  Wait Stop setup time and prep for SCL High time
                            andn    dira, SDAPin                    '4          '  SDA float  (Stop Condition)
                            waitcnt BitDelay, #0                    '6+[10+]    '  Wait SCL High time (no prep for next delay)
                            test    SDAPin,ina      wc                          '  Sample SDA; c = ready, nc = not ready
                if_nc       djnz    Bits, #:Loop                                'If SDA not high, loop until done
  EE_Jmp        if_nc       jmp     #EEFail                                     'If SDA still not high, abort

  EE_Stop_ret               ret                             

'***************************************
{Shutdown EEPROM and Propeller pin outputs}
  EE_Shutdown               mov     EE_Jmp, #0                                  'Deselect EEPROM (replace jmp with nop)         [Shutdown EEPROM]
                            call    #EE_Stop                                    '(always returns)
                            mov     dira, #0                                    'Cancel any outputs
  EE_Shutdown_ret           ret                                                 'Return




'***************************************
'*       Constants and Variables       *
'***************************************

{Initialized Variables}
  MemAddr       long    0                                                               'Address in Main RAM or External EEPROM
  Zero                                                                                  'Zero value (for clearing RAM) and
    Checksum    long    0                                                               '  Checksum (for verifying RAM)
                                                                             
{Constants}                                                                              
  Reset         long    %1000_0000                                                      'Propeller restart value (for CLK register)
  IncDest       long    %1_0_00000000                                                   'Value to increment a register's destination field
  EndOfRAM      long    $8000                                                           'Address of end of RAM+1
  CallFrame     long    $FFF9_FFFF                                                      'Initial call frame value
  Interpreter   long    $0001 << 18 + $3C01 << 4 + %0000                                'Coginit value to launch Spin interpreter
  RxPin         long    |< 31                                                           'Receive pin mask (P31)
  TxPin         long    |< 30                                                           'Transmit pin mask (P30)
  SDAPin        long    |< 29                                                           'EEPROM's SDA pin mask (P29)
  SCLPin        long    |< 28                                                           'EEPROM's SCL pin mask (P28)

{Host Initialized Values (values below are examples only)}                                                                
  BitTime                                                                               'Bit period (in clock cycles)
    IBitTime    long    80_000_000 / 115_200                     '[host init]           '  Initial bit period (at startup)
    FBitTime    long    80_000_000 / 230_400                     '[host init]           '  Final bit period (for download)
  BitTime1_5    long    TRUNC(1.5 * 80_000_000.0 / 230_400.0)    '[host init]           '1.5x bit period; used to align to center of received bits
  Timeout                                                                               'Timeout
    Failsafe    long    2 * 80_000_000 / (3 * 4)                 '[host init]           '  Failsafe timeout (2 seconds worth of Acknowledge:RxWait loop iterations)
    EndOfPacket long    2 * 80_000_000 / 230_400 * 10 * (3 * 4)  '[host init]           '  EndOfPacket timeout (2 bytes worth of Acknowledge:RxWait loop iterations)

  STime         long    trunc(80_000_000.0 * 0.000_000_6) #> 14  '[host init]           'Minimum EEPROM Start/Stop Condition setup/hold time (1/0.6 µs); [Min 14 cycles]
  SCLHighTime   long    trunc(80_000_000.0 * 0.000_000_6) #> 14  '[host init]           'Minimum EEPROM SCL high time (1/0.6 µs); [Min 14 cycles]
  SCLLowTime    long    trunc(80_000_000.0 * 0.000_001_3) #> 26  '[host init]           'Minimum EEPROM SCL low time (1/1.3 µs); [Min 26 cycles]
    
  ExpectedID    long    0                                        '[host init]           'Expected Packet ID; [For acknowledgements, RcvdTransID must follow!]
                                                                                         
{Reserved Variables}
  RcvdTransID                                                                           'Received Transmission ID (for acknowledgements) and
    PacketAddr  res     1                                                               '  PacketAddr (for receiving/copying packets)
  TimeDelay     res     1                                                               'Timout delay
  BitDelay      res     1                                                               'Bit time delay
  SByte         res     1                                                               'Serial Byte; received or to transmit; from/to Wi-Fi or EEPROM
  Longs         res     1                                                               'Long counter
  Bytes         res     1                                                               'Byte counter
  Bits          res     1                                                               'Bits counter
  Packet                                                                                'Packet buffer
    PacketID    res     1                                                               '  Header:  Packet ID number (unique per packet payload)
    TransID     res     1                                                               '  Header:  Transmission ID number (unique per host tranmission)
    PacketData  res     (MaxPayload / 4) - 2                                            '  Payload: Packet data (longs); (max size in longs) - header
        
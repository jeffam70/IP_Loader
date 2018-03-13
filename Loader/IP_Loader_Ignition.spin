{Object_Title_and_Purpose}


PUB public_method_name


DAT
{IP Loader PASM.  Runs in cog to receive target application at high-speed (compared to standard Propeller Download Protocol).

Timing: Critical routine timing is shown in comments, like '4 and '6+, indication clock cycles instruction consumes.
        'n       : n clock cycles
        'n+      : n or more clock cycles
        'n/m     : n cycles (if jumping) or m cycles (if not jumping)
        'x/n     : don't care (if executed) or n cycles (if not executed)
        'n![m+]  : n cycles til moment of output/input, routine's iteration time is m or more cycles moment-to-moment
        'n![m/l] : like above except inner-loop iteration time is m cycles moment-to-moment, outer-loop is l cycles moment-to-moment
        'n!(m)   : like above except m is last moment to this critical moment (non-iterative)

        * MaxRxSenseError : To support the FailSafe and EndOfPacket timeout feature, the :RxWait routine detects the edges of start bits with
                            a polling loop.  This means there's an amount of edge detection error equal to the largest number of clock cycles
                            starting from 1 cycle after input pin read to the moment the 1.5x bit period window is calculated.   This cycle
                            path is indicated in the :RxWait routine's comments along with the calculated maximum error.  This value should
                            be used as the MaxRxSenseError constant in the host software to adjust the 1.5x bit period downward so that the
                            bit sense moment is closer to ideal in practice.
}

'***************************************
'*              Ignition               *
'***************************************
{This is a small loader used only in a Chrome App on a macOS platform, which suffers from a max contiguous serial transmission size of 1,024 bytes.
In its encoded form, it fits (at the tail end of the leading connection overhead) within 1,024 bytes to ensure a successful initial application delivery,
then it executes to receive, store, and run the Micro Boot Loader (MBL) Core application image.
} 
                            org     0
                            {Relocate Ignition code beyond MBL code space}
  Relocate                  mov     Ignition{addr}, $+4{addr}                           'Relocate code line (to intended location, from emitted location)
                            add     Relocate, IncCodeLine                               'Increment pointers
                            djnz    ReloCount, #Relocate                                'Loop until all Ignition code relocated
                            jmp     #Ignition                                           'Jump to relocated Ignition code

                            org     $100
                            {Receive Micro Boot Loader Image}                          
  Ignition                  mov     IBytes, #4                      '4                  '  Ready for 1 long
    :NextCodeByte           mov     IBitDelay, IBitTime1_5  wc      '4                  '    Prep first bit sample window; c=0 for first :RxWait
                            mov     IByte, #0                       '4
    :RxWait                 muxc    IByte, #%0_1000_0000    wz      '4            ┌┐    '    Wait for Rx start bit (falling edge); Prep SByte for 8 bits; z=1 first time
                            test    IRxPin, ina             wc      '4![12/52/80]┐││    '      Check Rx state; c=0 (not resting), c=1 (resting)
              if_z_or_c     djnz    ITimeout, #:RxWait              '4/x         └┘│    '    No start bit (z or c)? loop until timeout
              if_z_or_c     jmp     #:TimedOut                      'x/4           │    '    No start bit (z or c) and timed-out? Exit
                            add     IBitDelay, cnt                  '4             ┴*23 '    Set time to...             (*See MaxRxSenseError note)
    :RxBit                  waitcnt IBitDelay, IBitTime             '6+                 '    Wait for center of bit    
                            test    IRxPin, ina             wc      '4![22/x/x]         '      Sample bit; c=0/1
                            muxc    IByte, #%1_0000_0000            '4                  '      Store bit
                            shr     IByte, #1               wc      '4                  '      Adjust result; c=0 (continue), c=1 (done)
              if_nc         jmp     #:RxBit                         '4                  '    Continue? Loop until done
    :Leader                 cmp     IByte, #$05{leader}     wz      '4                  '    Check for leader ($05); z=0 (not found), z=1 (found)
              if_nz{/if_z}  jmp     #:RxWait                        '4                  '    No leader (nz)? loop until start of leader; once found, loops until end of leader
              if_z          xor     $-1, InvCondition               '4                  '    Leader (z)? invert previous condition (to if_z) to look for end of leader
              if_z          jmp     #:RxWait                        '4                  '    Leader (z)? loop to find end of leader
                            movs    :Leader, #$1FF                  '4                  '    Leader done (nz)? prevent further leader matches
    :CodeAddr               andn    $0{addr}, #$FF                  '4                  '    Clear space,
                            or      $0{addr}, IByte                 '4                  '    store value into long (low byte first),
                            ror     $0{addr}, #8                    '4                  '    and adjust long
                            xor     IByte, ICount                   '4                  '    Calculate checksum
                            sub     IChecksum, IByte                '4
                            djnz    IBytes, #:NextCodeByte          '4/8                '  Loop for all bytes of long
                            add     :CodeAddr+0, IncCodeDest        '4                  '  Done, increment code pointers for next time
                            add     :CodeAddr+1, IncCodeDest        '4
                            add     :CodeAddr+2, IncCodeDest        '4
                            djnz    ICount, #Ignition               '4/8                'Loop for rest of MBL image
                            tjnz    IChecksum, #:TimedOut                               'Full image received; exit if checksum invalid
                            jmp     #$0                                                 'Checksum valid; run MBL

                            {Timed out}
    :TimedOut               clkset  IReset                                              'Restart Propeller

                                                                        
'***************************************
'*  Ignition Constants and Variables   *
'***************************************
                                                                             
{Constants}                                                                              
  IReset        long    %1000_0000                                              'Propeller restart value (for CLK register)
  IncCodeDest   long    %1_0_00000000                                           'Value to increment a register's destination field
  IncCodeLine   long    %1_0_00000001                                           'Value to increment a register's destination and source fields
  InvCondition  long    %00000_0000_1111_000000000_000000000                    'Value to invert condition field
  IRxPin        long    |< 31                                                   'Receive pin mask (P31)
  

{Host Initialized Values (values below are examples only)}                                                                
  ICount        long    0                                                       'Micro Boot Loader image size
  IChecksum     long    0                                                       'Checksum (for verifying Micro Boot Loader image)
  IBitTime      long    80_000_000 / 921_600                     '[host init]   'Bit period (for high-speed download of Micro Boot Loader)                                                                   'Bit period (in clock cycles)
  IBitTime1_5   long    TRUNC(1.5 * 80_000_000.0 / 921_600.0)    '[host init]   '1.5x bit period; used to align to center of received bits
  ITimeout      long    80_000_000 / (3 * 4)                     '[host init]   'Failsafe timeout (1 second worth of :RxWait loop iterations)


{Initialized Variables}
  ReloCount     long    ReloCount-Ignition                                      'Number of longs of Ignition code to relocate [Must be just before reserved variables]

{Reserved Variables}
  IBitDelay     res     1                                                       'Bit time delay
  IByte         res     1                                                       'Serial Byte; received or to transmit; from/to Wi-Fi or EEPROM
  IBytes        res     1                                                       'Byte counter (or byte value)
  
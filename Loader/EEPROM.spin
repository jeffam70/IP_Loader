{To-Do: Determine if nops are really needed... it doesn't seem possible for two signals to be too close to each other at this speed.
        Write verify routine.
        Write acknowledge/non-acknowledge routines.
        Verify timing at 80 MHz.
        Determine if any timing/code improvements can be made.}

{Done: Writes entire RAM in page-mode (64-bytes at a time).}

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

  EEFail                    jmp     #$                   

'***************************************
'* I2C routines for 24xC256/512 EEPROM *
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
  EE_StartWrite             mov     Longs, #511                                 '>5ms of EE Ack attempts @80MHz (1MHz protocol) [Wake EEPROM, Start EEPROM Write]
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
                            mov     BitDelay, SCLLowTime                        'Prep for SCL Low time
                            add     BitDelay, cnt                                
    :Loop                   andn    outa, SCLPin                                'Ready SCL low
                            or      dira, SCLPin                                '  SCL low
                            nop                                                 '  Tiny delay; ensures SCL low before SDA rise
                            andn    dira, SDAPin                                '  SDA float
                            waitcnt BitDelay, STime                             '  Wait SCL Low time and prep for Start Setup time
                            or      outa, SCLPin                                '  SCL high
                            waitcnt BitDelay, STime                             '  Wait Start Setup time and prep for Start Hold time
                            test    SDAPin, ina             wc                  '  Sample SDA; c = ready, nc = not ready
                if_nc       djnz    Bits, #:Loop                                'SDA not high?  Loop until exhausted attempts
                if_nc       jmp     #EEFail                                     'SDA still not high?  Abort
                            or      dira, SDAPin                                'SDA low  (Start Condition)
                            waitcnt BitDelay, #0                                'Wait Start Hold time (no prep for next delay)
                        
'***************************************
{Transmit to or receive from EEPROM.
 On return: c = NAK, nc = ACK.}
  EE_Transmit               shl     SByte, #1                                   'Ready to transmit byte and receive ACK  [Transmit/Receive]
                            or      SByte, #%00000000_1                          
                            jmp     #EE_TxRx                                     
  EE_Receive                mov     SByte, #%11111111_0                         'Ready to receive byte and transmit ACK
  EE_TxRx                   mov     Bits, #9                                    'Set for 9 bits (8 data + 1 ACK (if Tx))
                            mov     BitDelay, SCLLowTime                        'Prep for SCL Low time
                            add     BitDelay, cnt                                
    :Loop                   andn    outa, SCLPin                                'SCL low
                            test    SByte, #$100            wz                  '  Get next SDA output state; z=bit
                            rcl     SByte, #1                                   '  Shift in prior SDA input state
                            muxz    dira, SDAPin                                '  Generate SDA state (SDA low/float)
                            waitcnt BitDelay, SCLHighTime                       '  Wait SCL Low time and prep for SCL High time
                            test    SDAPin, ina             wc                  '  Sample SDA
                            or      outa, SCLPin                                '  SCL high
                            waitcnt BitDelay, SCLLowTime                        '  Wait SCL High time and prep for SCL Low time
                            djnz    Bits, #:Loop                                'If another bit, loop
                            and     SByte, #$FF                                 'Isolate byte received
  EE_Receive_ret
  EE_Transmit_ret
  EE_Start_ret              ret                                                 'nc = ACK

'***************************************
{Stop EEPROM operation}
  EE_Stop                   mov     Bits, #9                                    'Ready 9 stop attempts                          [Stop]
    :Loop                   andn    outa, SCLPin                                'SCL low
                            mov     BitDelay, cnt                                
                            add     BitDelay, SCLLowTime                        '  Prep for SCL low time
                            or      dira, SDAPin                                '  SDA low
                            waitcnt BitDelay, STime                             '  Wait SCL Low time and prep for Stop setup time
                            or      outa, SCLPin                                '  SCL high
                            waitcnt BitDelay, SCLHighTime                       '  Wait Stop setup time and prep for SCL High time
                            andn    dira, SDAPin                                '  SDA float  (Stop Condition)
                            waitcnt BitDelay, #0                                '  Wait SCL High time (no prep for next delay)
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

  STime         long    trunc(80_000_000.0 * 0.000_000_6)        '[host init]           'Minimum EEPROM Start/Stop Condition setup/hold time (1/0.6 µs)
  SCLHighTime   long    trunc(80_000_000.0 * 0.000_000_6)        '[host init]           'Minimum EEPROM SCL high time frequency (1/0.6 µs)
  SCLLowTime    long    trunc(80_000_000.0 * 0.000_001_3)        '[host init]           'Minimum EEPROM SCL low time frequency (1/1.3 µs)
    
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
        
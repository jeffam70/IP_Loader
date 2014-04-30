CON
        _clkmode = xtal1 + pll16x                                               'Standard clock mode * crystal frequency = 80 MHz
        _xinfreq = 5_000_000

PUB Main

  waitcnt(clkfreq + cnt)

  coginit(0, @Loader, 0)

DAT
                        org     0
  Loader                mov     outa, TxPin                                     'Initialize Tx Pin to output high (resting state)
                        mov     dira, TxPin
                        
                        mov     SByte, #$0                                      'Transmit boot acknowledgement; at initial baud rate
                        call    #Tx
                        mov     SByte, #$AB
    :Loop               call    #Tx
                        call    #Rx
                        jmp     #:Loop
                        
{***************************************
 *             Subroutines             *
 ***************************************}

{Transmit byte to host.
 Requirements:  SByte must contain desired byte value to transmit.}

  Tx                    or      SByte, #%1_0000_0000                            'Append stop bit
                        shl     SByte, #1                                       'Prepend start bit
                        mov     Bits, #10                                       'Ready 10 bits
                        mov     BitDelay, BitTime                               'Prep first bit window
                        add     BitDelay, cnt
                        
    :TxBit              shr     SByte, #1               wc                      'Get next bit
                        waitcnt BitDelay, BitTime                               'Wait for edge of bit window
                        muxc    outa, TxPin                                     'Output next bit
                        djnz    Bits, #:TxBit                                   'Loop for next bit                        
  Tx_ret                ret                                                     'Done; return                  

'***************************************

{Receive byte from host.
 Requirements:  None; received byte will be placed into SByte.}

  Rx                    mov     TimeDelay, Timeout                              'Reset timeout delay
                        mov     BitDelay, BitTime1_5                            'Prep for first bit sample
                        mov     Bits, #8                                        'Ready for 8 bits
    :RxByte             test    RxPin, ina              wc                      'Rx pin resting? c=yes
              if_c      djnz    TimeDelay, #:RxByte                             '  If yes, loop until timeout
              if_c      clkset  Restart                                         'Timed-out? Reset Propeller
                        add     BitDelay, cnt
    :RxBit              waitcnt BitDelay, BitTime                               'Wait for center of bit
'                       xor     outa, TxPin
                        test    RxPin, ina              wc                      'Sample bit
                        shr     SByte, #1                                       'Adjust result and store bit
                        muxc    SByte, #%1000_0000                              'Store bit
                        djnz    Bits, #:RxBit
  Rx_ret                ret                                                     'Done; return

'***************************************
'*       Constants and Variables       *
'***************************************

{Constants}
  Restart     long      %1000_0000                                              'Reboot value (for CLK register)
  RxPin       long      |< 31                                                   'Receive pin mask (P31)
  TxPin       long      |< 30                                                   'Transmit pin mask (P30)
  BitTime     long      80_000_000 / 230_400                                    'Bit period (in clock cycles)
  BitTime1_5  long      TRUNC(1.5 * 80_000_000.0 / 230_400.0)                   '1.5x bit period; used to align to center of received bits
  Timeout     long      80_000_000 * 4 / (2*8)                                  'Timeout period (2 seconds worth of RxByte loop iterations)

{Variables}
  TimeDelay   res       1                                                       'Timout delay
  BitDelay    res       1                                                       'Bit time delay
  SByte       res       1                                                       'Byte to transmit, or byte received
  Bits        res       1                                                       'Bit counter


' CalcBitTime           mov     BitTime1_5, BitTime                             'Calculate 1.5x bit time (BitTime * 3 / 2)
'                       shl     BitTime1_5, #1
'                       add     BitTime1_5, BitTime
'                       shr     BitTime1_5, #1


'Possibly adjust BitTime1_5 by sample loop time to true it up
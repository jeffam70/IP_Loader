DAT
                            {First ACK serves as "Ready" signal at initial baud rate}
                            {Send ACK/NAK + TID (Transmission ID)}
  Acknowledge               movd    :TxBit, #ExpectedID                                 'ACK=next packet ID, NAK=previous packet ID, TID=ID of transmission prompting this response                                  
                            mov     Longs, #64                                          'Ready 2 longs-worth of bits
                            mov     BitDelay, BitTime                                   'Prep start bit window / ensure prev. stop bit window
                            add     BitDelay, cnt

    :TxByte                 waitcnt BitDelay, BitTime               '6+                 '    Wait for edge of start bit window
                            andn    outa, TxPin                     '4!(18+)            '    Output start bit (low)
    :TxBit                  ror     ExpectedID{addr}, #1    wc      '4                  '    Get next data bit
                            waitcnt BitDelay, BitTime               '6+                 '      Wait for edge of data bit window
                            muxc    outa, TxPin                     '4![18+]            '      Output data bit
                            sub     Longs, #1
                            and     Longs, #%000111         wz
              if_z          waitcnt BitDelay, BitTime               '6+                 '    Wait for edge of stop bit window
              if_z          or      outa, TxPin                     '4!(18+)            '    Output stop bit (high)
                            and     Longs, #%011111         wz
              if_nz         jmp     #:TxBit
              if_z          add     :TxBit, IncDest                 '4                  '  Get next long
                            tjnz    Longs, #:TxByte                 '4/8                'Loop for next long

                            

                            djnz    Bits, #:TxBit                   '4/8                '    Loop for next data bit

                            djnz    Bytes, #:TxByte                 '4/8                '  Loop for next byte of long
                            add     :TxBit, IncDest                 '4                  '  Get next long
                            djnz    Longs, #:TxLong                 '4/8                'Loop for next long

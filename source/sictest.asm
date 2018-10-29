test     start   1000              test program for sic software
first    stl     retadr            save return address
cloop    jsub    rdrec             read input record
         lda     length            test for eof (length = 0 
         comp    zero                eol == 1) 
         jeq     endfil            exit if eof found
         jsub    wrrec             write output record
         j       cloop             loop 
endfil   lda     eof               insert end of file marker
         sta     buffer 
         lda     three             set length = 3 
         sta     length 
         jsub    wrrec             write eof
         ldl     retadr            get return address 
         rsub                      return to caller 
eof      byte    c'EOF' 
three    word    3
zero     word    0
one      word    1
k5       word    5
k11      word    11
retadr   resw    1
length   resw    1
buffer   resb    4096              4096-byte buffer area
. 
.       subroutine to read record into buffer
. 
rdrec    ldx     zero              clear loop counter 
         lda     zero              clear a to zero
rloop    td      input             test input device
         jeq     rloop             loop until ready 
         rd      input             read character into register a 
         comp    k11               test for eol or eof
         jlt     exit              exit loop if found 
         stch    buffer,x          store character in buffer
         tix     maxlen            loop unless max length 
         jlt     rloop                 has been reached 
exit     stch    buffer,x          store eol/eof in buffer
         stx     length            save record length 
         comp    k5
         jlt     endrd
         lda     length            modify record length to include
         add     one                 eol 
         sta     length 
endrd    rsub                      return to caller 
input    byte    x'f3'             code for input device
maxlen   word    4096 
. 
.       subroutine to write record from buffer 
. 
wrrec    ldx     zero              clear loop counter 
wloop    td      output            test output device 
         jeq     wloop             loop until ready 
         ldch    buffer,x          get character from buffer
         wd      output            write character
         tix     length            loop until all characters
         jlt     wloop                have been written 
         rsub                      return to caller 
output   byte    x'06'             code for output device 
         end     first

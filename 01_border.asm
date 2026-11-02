; WHAT: Change border and background colours and draw a red A.
; WHY: A first program should prove that loading, SYS and hardware stores work.
; HOW: LDA # loads a number; STA writes it to a VIC register or a screen cell.
; Run separately from the game. Reset to normal PAL BASIC first.
!cpu 6510 ; Select the C64 CPU instruction set while assembling this file.
* = $0801 ; Place subsequent bytes at this address; this is an assembler origin.
; Emit these byte values in order; table and bitmap layout depends on them.
!byte $0c,$08,$0a,$00,$9e,$32,$30,$36,$34,$00,$00,$00
* = $0810 ; Place subsequent bytes at this address; this is an assembler origin.
; Choose a colour in A, then store that same value at its destination.
start: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #0 ; Put the literal 0 in A; # selects a value; N/Z reflect it.
    sta $d020 ; Write A to border colour; a store leaves the CPU flags unchanged.
    lda #7 ; Put the literal 7 in A; # selects a value; N/Z reflect it.
    sta $d021 ; Write A to background colour; a store leaves the CPU flags unchanged.
; Screen code $01 is A in the normal uppercase character set.
    lda #1 ; Put the literal 1 in A; # selects a value; N/Z reflect it.
    sta $0400 ; Write A to $0400; a store leaves the CPU flags unchanged.
    lda #2 ; Put the literal 2 in A; # selects a value; N/Z reflect it.
    sta $d800 ; Write A to $d800; a store leaves the CPU flags unchanged.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

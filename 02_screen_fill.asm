; WHAT: Fill exactly 1000 character cells and their matching colour entries.
; WHY: X only holds 0..255, so four 250-byte blocks cover the whole display.
; HOW: Use the same offset for each screen/colour pair; stop when X reaches 250.
; Run separately from the game. Reset to normal PAL BASIC first.
!cpu 6510 ; Select the C64 CPU instruction set while assembling this file.
* = $0801 ; Place subsequent bytes at this address; this is an assembler origin.
; Emit these byte values in order; table and bitmap layout depends on them.
!byte $0c,$08,$0a,$00,$9e,$32,$30,$36,$34,$00,$00,$00
* = $0810 ; Place subsequent bytes at this address; this is an assembler origin.
start: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #0 ; Put the literal 0 in A; # selects a value; N/Z reflect it.
    sta $d020 ; Write A to border colour; a store leaves the CPU flags unchanged.
    sta $d021 ; Write A to background colour; a store leaves the CPU flags unchanged.
; Start with the first byte in each of the four 250-byte blocks.
    ldx #0 ; Put the literal 0 in X; # selects a value; N/Z reflect it.
; WHAT: write one asterisk into each block.
; WHY: four stores per X value cover 4 x 250 cells without X overflowing.
fill_loop: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #42 ; Put the literal 42 in A; # selects a value; N/Z reflect it.
    sta $0400,x ; Write A to $0400,x; a store leaves the CPU flags unchanged.
    sta $04fa,x ; Write A to $04fa,x; a store leaves the CPU flags unchanged.
    sta $05f4,x ; Write A to $05f4,x; a store leaves the CPU flags unchanged.
    sta $06ee,x ; Write A to $06ee,x; a store leaves the CPU flags unchanged.
; HOW: copy the index to A, then AND $0F keeps only its low four bits.
; The resulting 0..15 value selects a valid C64 foreground colour.
    txa ; Copy X to A; N/Z reflect the copied byte.
    and #$0f ; Keep only bits shared with #$0f; A and N/Z change; carry is preserved.
    sta $d800,x ; Write A to $d800,x; a store leaves the CPU flags unchanged.
    sta $d8fa,x ; Write A to $d8fa,x; a store leaves the CPU flags unchanged.
    sta $d9f4,x ; Write A to $d9f4,x; a store leaves the CPU flags unchanged.
    sta $daee,x ; Write A to $daee,x; a store leaves the CPU flags unchanged.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
; X=250 means indices 0..249 are finished; Z=1 makes BNE stop.
    cpx #250 ; Compare X with #250; set N/Z/C without changing X; C means >= unsigned.
; Branch to fill_loop when Z=0 (nonzero/not equal); otherwise continue in sequence.
    bne fill_loop
    rts ; Pull the saved call address and add one; resume after the calling JSR.

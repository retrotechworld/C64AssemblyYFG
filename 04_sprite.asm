; WHAT: Display one red sprite at horizontal position 280.
; WHY: 280 does not fit in an eight-bit X register: we must set the ninth bit.
; HOW: Select bank 0, point to the bitmap and set low X=$18 plus $D010 bit 0.
; Run separately from the game. Reset to normal PAL BASIC first.
!cpu 6510 ; Select the C64 CPU instruction set while assembling this file.
* = $0801 ; Place subsequent bytes at this address; this is an assembler origin.
; Emit these byte values in order; table and bitmap layout depends on them.
!byte $0c,$08,$0a,$00,$9e,$32,$30,$36,$34,$00,$00,$00
* = $0810 ; Place subsequent bytes at this address; this is an assembler origin.
; Make the CIA2 bank-select pins outputs and select VIC bank 0.
start: ; Name the address of the next emitted byte; a label emits no bytes.
    lda $dd02 ; Read $dd02 into A; update N/Z without changing carry.
    ora #3 ; Set A bits selected by #3; preserve other bits and carry; update N/Z.
    sta $dd02 ; Write A to $dd02; a store leaves the CPU flags unchanged.
    lda $dd00 ; Read $dd00 into A; update N/Z without changing carry.
    ora #3 ; Set A bits selected by #3; preserve other bits and carry; update N/Z.
    sta $dd00 ; Write A to $dd00; a store leaves the CPU flags unchanged.
; Select the default screen at $0400 and ROM character patterns.
    lda #$14 ; Put the literal $14 in A; # selects a value; N/Z reflect it.
; Write A to screen and character selection; a store leaves the CPU flags unchanged.
    sta $d018
    lda #0 ; Put the literal 0 in A; # selects a value; N/Z reflect it.
    sta $d01c ; Write A to $d01c; a store leaves the CPU flags unchanged.
    sta $d017 ; Write A to $d017; a store leaves the CPU flags unchanged.
    sta $d01d ; Write A to $d01d; a store leaves the CPU flags unchanged.
    sta $d01b ; Write A to $d01b; a store leaves the CPU flags unchanged.
    sta $d020 ; Write A to border colour; a store leaves the CPU flags unchanged.
    sta $d021 ; Write A to background colour; a store leaves the CPU flags unchanged.
; WHY $C0: the sprite pointer is $3000 / 64 within bank 0.
    lda #$c0 ; Put the literal $c0 in A; # selects a value; N/Z reflect it.
    sta $07f8 ; Write A to sprite-0 bitmap pointer; a store leaves the CPU flags unchanged.
; HOW 280 is split: $0118 has low byte $18 and high bit 1.
    lda #$18 ; Put the literal $18 in A; # selects a value; N/Z reflect it.
    sta $d000 ; Write A to $d000; a store leaves the CPU flags unchanged.
    lda #100 ; Put the literal 100 in A; # selects a value; N/Z reflect it.
    sta $d001 ; Write A to $d001; a store leaves the CPU flags unchanged.
    lda #1 ; Put the literal 1 in A; # selects a value; N/Z reflect it.
; This standalone lab owns all sprite channels, so it may write a full mask.
    sta $d010 ; Write A to sprite ninth-X-bit mask; a store leaves the CPU flags unchanged.
    sta $d015 ; Write A to sprite enable mask; a store leaves the CPU flags unchanged.
    lda #2 ; Put the literal 2 in A; # selects a value; N/Z reflect it.
    sta $d027 ; Write A to $d027; a store leaves the CPU flags unchanged.
    rts ; Pull the saved call address and add one; resume after the calling JSR.
; WHAT: reserve one aligned sprite block: 63 bitmap bytes and a pad byte.
; WHY $FF: eight one-bits light all pixels, making a simple solid block.
* = $3000 ; Place subsequent bytes at this address; this is an assembler origin.
!fill 63,$ff ; Emit the requested number of initial bytes for this array or data block.
!byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.

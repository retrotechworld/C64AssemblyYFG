; WHAT: Copy a zero-terminated message to screen RAM.
; WHY: Direct screen stores need screen codes, so the data uses !scr.
; HOW: X selects one byte; BEQ stops at zero; INX advances to the next byte.
; Run separately from the game. Reset to normal PAL BASIC first.
!cpu 6510 ; Select the C64 CPU instruction set while assembling this file.
* = $0801 ; Place subsequent bytes at this address; this is an assembler origin.
; Emit these byte values in order; table and bitmap layout depends on them.
!byte $0c,$08,$0a,$00,$9e,$32,$30,$36,$34,$00,$00,$00
* = $0810 ; Place subsequent bytes at this address; this is an assembler origin.
start: ; Name the address of the next emitted byte; a label emits no bytes.
    ldx #0 ; Put the literal 0 in X; # selects a value; N/Z reflect it.
; WHAT: fetch the next message byte using X as its position.
; HOW: LDA sets Z when the terminator is zero; BEQ exits before storing it.
copy: ; Name the address of the next emitted byte; a label emits no bytes.
; Read message,x at the indexed element into A; update N/Z, preserve carry.
    lda message,x
    beq done ; Branch to done when Z=1 (zero/equal); otherwise continue in sequence.
    sta $0400,x ; Write A to $0400,x; a store leaves the CPU flags unchanged.
; Colour RAM is separate from character RAM; make each letter white.
    lda #1 ; Put the literal 1 in A; # selects a value; N/Z reflect it.
    sta $d800,x ; Write A to $d800,x; a store leaves the CPU flags unchanged.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    bne copy ; Branch to copy when Z=0 (nonzero/not equal); otherwise continue in sequence.
done: ; Name the address of the next emitted byte; a label emits no bytes.
    rts ; Pull the saved call address and add one; resume after the calling JSR.
; WHY !scr: lowercase source letters give uppercase screen codes.
; The final zero belongs to our copy-loop convention, not to the VIC.
message: ; Name the address of the next emitted byte; a label emits no bytes.
; Emit screen-code characters for direct screen RAM, not KERNAL text I/O.
    !scr "hello from 6510"
    !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.

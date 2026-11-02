; WHAT: Add four to the 16-bit number $00FE and display the high result.
; WHY: Each CPU arithmetic operation handles only one byte, so carry joins two.
; HOW: Add low bytes first; keep their carry for the high ADC; expect $0102.
; Run separately from the game. Reset to normal PAL BASIC first.
!cpu 6510 ; Select the C64 CPU instruction set while assembling this file.
* = $0801 ; Place subsequent bytes at this address; this is an assembler origin.
; BASIC line 10 SYS 2064 enters machine code at $0810.
; Emit these byte values in order; table and bitmap layout depends on them.
!byte $0c,$08,$0a,$00,$9e,$32,$30,$36,$34,$00,$00,$00
* = $0810 ; Place subsequent bytes at this address; this is an assembler origin.
start: ; Name the address of the next emitted byte; a label emits no bytes.
    cld ; Use binary addition, not decimal mode.
    clc ; Begin with no carry coming into the low byte.
    lda #$fe ; A = low byte of $00FE, decimal 254.
    adc #4 ; 254+4=258: A wraps to $02 and C becomes 1.
    sta low_value ; Save low result. STA leaves carry unchanged.
    lda #0 ; A = high byte. LDA also leaves carry unchanged.
    adc #0 ; Add 0 plus C=1: high result becomes $01.
    sta high_value ; Together the saved bytes now represent $0102.
; Carry belongs to the multi-byte sum until its high byte is complete.
; We may now clear it for a separate calculation: making a screen digit.
    clc ; Clear carry before a new independent addition; do not break a byte-to-byte chain.
    adc #$30 ; High value 1 + digit-zero code $30 = digit 1.
    sta $0400 ; Write that digit into the first screen cell.
; Foreground colour 1 is white.. Put the literal 1 in A; # selects a value; N/Z reflect
; it.
    lda #1
    sta $d800 ; Give the displayed digit a visible colour.
; Return to the BASIC SYS caller.. Pull the saved call address and add one; resume after
; the calling JSR.
    rts
low_value: !byte 0 ; One byte of RAM for the low result.
high_value: !byte 0 ; One byte of RAM for the high result.

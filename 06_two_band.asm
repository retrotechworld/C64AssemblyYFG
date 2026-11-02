; WHAT: Show two logical objects with the same physical sprite channel.
; WHY: A sprite channel can be reused once its first 21-line picture finishes.
; HOW: IRQs at lines 40 and 140 prepare sprite 0 for Y=80 then Y=160.
; Run separately from the game. Reset to normal PAL BASIC first.
!cpu 6510 ; Select the C64 CPU instruction set while assembling this file.
* = $0801 ; Place subsequent bytes at this address; this is an assembler origin.
; Emit these byte values in order; table and bitmap layout depends on them.
!byte $0c,$08,$0a,$00,$9e,$32,$30,$36,$34,$00,$00,$00
* = $0810 ; Place subsequent bytes at this address; this is an assembler origin.
; Disable IRQs until the vector, sprite mode and first compare are ready.
start: ; Name the address of the next emitted byte; a label emits no bytes.
    sei ; Mask normal IRQ service while shared setup is incomplete; NMI is separate.
    lda $dd02 ; Read $dd02 into A; update N/Z without changing carry.
    ora #3 ; Set A bits selected by #3; preserve other bits and carry; update N/Z.
    sta $dd02 ; Write A to $dd02; a store leaves the CPU flags unchanged.
    lda $dd00 ; Read $dd00 into A; update N/Z without changing carry.
    ora #3 ; Set A bits selected by #3; preserve other bits and carry; update N/Z.
    sta $dd00 ; Write A to $dd00; a store leaves the CPU flags unchanged.
    lda #$14 ; Put the literal $14 in A; # selects a value; N/Z reflect it.
; Write A to screen and character selection; a store leaves the CPU flags unchanged.
    sta $d018
    lda #0 ; Put the literal 0 in A; # selects a value; N/Z reflect it.
    sta $d017 ; Write A to $d017; a store leaves the CPU flags unchanged.
    sta $d01b ; Write A to $d01b; a store leaves the CPU flags unchanged.
    sta $d01c ; Write A to $d01c; a store leaves the CPU flags unchanged.
    sta $d01d ; Write A to $d01d; a store leaves the CPU flags unchanged.
    sta $d010 ; Write A to sprite ninth-X-bit mask; a store leaves the CPU flags unchanged.
    lda #$c0 ; Put the literal $c0 in A; # selects a value; N/Z reflect it.
    sta $07f8 ; Write A to sprite-0 bitmap pointer; a store leaves the CPU flags unchanged.
    lda #1 ; Put the literal 1 in A; # selects a value; N/Z reflect it.
    sta $d015 ; Write A to sprite enable mask; a store leaves the CPU flags unchanged.
    lda #0 ; Put the literal 0 in A; # selects a value; N/Z reflect it.
    sta band ; Write A to band; a store leaves the CPU flags unchanged.
; HOW: < selects the low address byte; > selects the high address byte.
    lda #<irq ; Put the literal <irq in A; # selects a value; N/Z reflect it.
; Write A to KERNAL IRQ vector low byte; a store leaves the CPU flags unchanged.
    sta $0314
    lda #>irq ; Put the literal >irq in A; # selects a value; N/Z reflect it.
; Write A to KERNAL IRQ vector high byte; a store leaves the CPU flags unchanged.
    sta $0315
    lda $d011 ; Read $d011 into A; update N/Z without changing carry.
    and #$7f ; Keep only bits shared with #$7f; A and N/Z change; carry is preserved.
    sta $d011 ; Write A to $d011; a store leaves the CPU flags unchanged.
; Schedule the first update before the upper picture starts at Y=80.
    lda #40 ; Put the literal 40 in A; # selects a value; N/Z reflect it.
    sta $d012 ; Write A to $d012; a store leaves the CPU flags unchanged.
    lda #1 ; Put the literal 1 in A; # selects a value; N/Z reflect it.
; Write A to VIC interrupt status/acknowledge; a store leaves the CPU flags unchanged.
    sta $d019
    sta $d01a ; Write A to VIC interrupt enables; a store leaves the CPU flags unchanged.
    cli ; Allow maskable IRQ service after the vector and hardware state are ready.
forever: ; Name the address of the next emitted byte; a label emits no bytes.
    jmp forever ; Continue at forever without saving a subroutine return address.
; WHAT: distinguish the VIC raster request from a CIA-only IRQ.
; WHY: acknowledge only the source handled here, then retain KERNAL service.
irq: ; Name the address of the next emitted byte; a label emits no bytes.
; Read VIC interrupt status/acknowledge into A; update N/Z without changing carry.
    lda $d019
    and #1 ; Keep only bits shared with #1; A and N/Z change; carry is preserved.
    beq exit_irq ; Branch to exit_irq when Z=1 (zero/equal); otherwise continue in sequence.
; Write A to VIC interrupt status/acknowledge; a store leaves the CPU flags unchanged.
    sta $d019
; band selects which display slot this raster event will prepare.
    lda band ; Read band into A; update N/Z without changing carry.
; Branch to lower_band when Z=0 (nonzero/not equal); otherwise continue in sequence.
    bne lower_band
    lda #80 ; Put the literal 80 in A; # selects a value; N/Z reflect it.
    sta $d000 ; Write A to $d000; a store leaves the CPU flags unchanged.
    sta $d001 ; Write A to $d001; a store leaves the CPU flags unchanged.
    lda #2 ; Put the literal 2 in A; # selects a value; N/Z reflect it.
    sta $d027 ; Write A to $d027; a store leaves the CPU flags unchanged.
; Schedule the next IRQ after the first picture ends and before Y=160.
    lda #140 ; Put the literal 140 in A; # selects a value; N/Z reflect it.
    sta $d012 ; Write A to $d012; a store leaves the CPU flags unchanged.
    lda #1 ; Put the literal 1 in A; # selects a value; N/Z reflect it.
    sta band ; Write A to band; a store leaves the CPU flags unchanged.
    jmp exit_irq ; Continue at exit_irq without saving a subroutine return address.
; Reuse physical sprite 0 for its second position and colour.
lower_band: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #200 ; Put the literal 200 in A; # selects a value; N/Z reflect it.
    sta $d000 ; Write A to $d000; a store leaves the CPU flags unchanged.
    lda #160 ; Put the literal 160 in A; # selects a value; N/Z reflect it.
    sta $d001 ; Write A to $d001; a store leaves the CPU flags unchanged.
    lda #5 ; Put the literal 5 in A; # selects a value; N/Z reflect it.
    sta $d027 ; Write A to $d027; a store leaves the CPU flags unchanged.
; Schedule the first update before the upper picture starts at Y=80.
    lda #40 ; Put the literal 40 in A; # selects a value; N/Z reflect it.
    sta $d012 ; Write A to $d012; a store leaves the CPU flags unchanged.
    lda #0 ; Put the literal 0 in A; # selects a value; N/Z reflect it.
    sta band ; Write A to band; a store leaves the CPU flags unchanged.
; Entry used the standard KERNAL register saves; $EA31 continues service.
exit_irq: ; Name the address of the next emitted byte; a label emits no bytes.
    jmp $ea31 ; Continue at $ea31 without saving a subroutine return address.
band: !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
* = $3000 ; Place subsequent bytes at this address; this is an assembler origin.
!fill 63,$ff ; Emit the requested number of initial bytes for this array or data block.
!byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.

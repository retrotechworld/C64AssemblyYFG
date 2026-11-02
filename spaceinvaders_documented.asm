; STARTING GAMES PROGRAMMING WITH C64 ASSEMBLY LANGUAGE — HELD INPUT EDITION
; Hold A/D or use joystick port 2. Space/button fires; Q ends; P replays.
; Deflected joystick directions take movement priority; opposing directions cancel.
; Updated game: detailed instruction comments do not change its executable bytes.
; SPACE INVADERS FOR THE COMMODORE 64 - FULL BEGINNER COMMENTED EDITION
; Assemble: acme -f cbm -o spaceinvaders.prg <this_filename.asm>
; Load the resulting PRG in VICE and type RUN if necessary.

; CONTROLS: hold A/D or use joystick port 2; Space/button fires; Q ends; P replays.
; READING THIS TEACHING EDITION
; Work through the routines in this order: START -> MAIN_LOOP ->
; READ_KEYBOARD -> UPDATE_BULLET -> BULLET_CHECK_COLLISION ->
; REDRAW_ALIENS -> RENDER_ALIENS -> NEXT_WAVE -> GAME_OVER.

; Important distinctions:
; LDA #$10    loads the NUMBER 16.
; LDA $10     loads the BYTE STORED at zero-page address $0010.
; LDA table,X reads an array element selected by index register X.
; STA ($fb),Y writes through a two-byte zero-page address pointer.
; CLC / ADC  add bytes, including carry from a lower byte.
; SEC / SBC  subtract bytes, including a borrow from a lower byte.
; CMP / BCC compare UNSIGNED values; BEQ checks the zero flag.
; JSR / RTS  call a routine and return using the hardware stack.

; The C64's 6510 has only 8-bit A, X and Y registers. To represent
; horizontal coordinates beyond 255, the game uses LOW and HIGH bytes.
; Example: x=$0120 means low=$20, high=$01, total decimal 288.

; Aliens use custom 8x8 text characters, THREE cells per shifted alien.
; The renderer caches actual drawn pixel coordinates in alien_draw_x,
; alien_draw_x_hi and alien_draw_y. The collision routine reads those
; same cached coordinates to avoid killing a neighbouring alien.
; Horizontal positions are now exact; vertical drops remain cell-aligned.

; A bullet is sprite 7. Its picture has transparent outer pixels,
; so the hit test uses the visible bolt's pixel offsets rather than
; treating all 24 sprite columns as solid.

; The main loop waits for a video frame and uses game_ticks to control
; alien movement. CHOOSE_ALIEN_DELAY returns fewer ticks as the
; aliens_remaining counter decreases, increasing their speed.

; Assembly source comments do NOT change the program's machine code.
; This revision adds pixel-shifted glyphs and a buffered raster-safe renderer.


; BEGINNER REFERENCE:
; 6510: the C64's processor. A, X and Y are its three main registers.
; $1234: a hexadecimal number/address. #$10: immediate constant 16.
; LDA loads A; LDX loads X; LDY loads Y; STA stores A into memory.
; JSR calls a routine; RTS returns. JMP always jumps to a label.
; CMP compares; BEQ branches if equal; BNE if not equal.
; BCC branches if carry is clear; BCS if carry is set.
; CLC clears carry; SEC sets carry before addition/subtraction.
; INC/DEC change a memory byte; INX/DEX change X; INY/DEY change Y.
; !byte places bytes in memory; !fill reserves initialized bytes.
; ; starts a comment; comments never become machine instructions.

; MEMORY MAP:
; $0400-$07E7  Screen characters (40 columns x 25 rows)
; $D800-$DBE7  Colour RAM (one colour per character cell)
; $D000-$D02E  VIC-II sprite, raster and colour registers
; $D400-$D418  SID sound chip registers
; $2000 onward Sprite pixel patterns (64 bytes per sprite)

; HOW THE GAME WORKS:
; 1. START sets up graphics, variables, sprites and interrupts.
; 2. MAIN_LOOP waits for a frame, then samples held keys and joystick port 2.
; 3. Every 8..2 frames aliens advance two visible pixels (faster as killed).
; 4. Bullets, shields, lives and score update during gameplay.
; 5. When all 24 aliens die, NEXT_WAVE builds a new formation.
; 6. The HUD shows WAVE: 001, WAVE: 002, and so on.
; 7. GAME OVER waits for P and then re-enters START.

; WHY ALIENS DO NOT FLICKER AS MUCH:
; They use two custom 8x8 character cells each, not 24 sprites.
; Old cells are erased in hidden RAM, then complete rows are published.
; Shields are kept on-screen and updated only when damaged.

; IMPORTANT: Keep the collision calculations and displayed alien
; coordinates together: earlier versions had mismatches causing misses.
; Hidden screen: $5000-$53ff; hidden colours: $5400-$57ff.
; Extra rendering routines and shifted patterns: $4000-$4fff.


; !to "spaceinvaders_sprites.prg", cbm
!cpu 6510 ; Select the C64 CPU instruction set while assembling this file.

; C64 SPACE INVADERS
; A = move left, D = move right, SPACE = fire, Q = quit.
; NEW: Aliens fire downward. Three enemy shots, ship lives and brief invulnerability.
; All 24 aliens use character graphics; sprite 7 is reserved for the bullet.
; Sprite 0 is dedicated to the player; no sprite multiplexing is needed.
; NOTE: If your build task supplies the output filename itself,
; remove the !to line at the top to avoid ACME's "Output file already chosen".

; Screen RAM: $0400
; Sprite data: $2000
; Alien sprite pointer: $80
; Player sprite pointer: $81
; Bullet sprite pointer: $82



SCREEN    = $0400 ; Screen character RAM (40 x 25 cells)
COLOR     = $D800 ; Per-character colour RAM. Define a symbolic constant at assembly time; no instruction runs here.
BORDER    = $D020 ; VIC-II border colour. Define a symbolic constant at assembly time; no instruction runs here.
BGCOLOR   = $D021 ; VIC-II background colour. Define a symbolic constant at assembly time; no instruction runs here.

ptr       = $fb ; Zero-page pointer reserved for indirect addressing
color_ptr = $fd ; Zero-page colour pointer (not currently used below)

* = $0801 ; Place subsequent bytes at this address; this is an assembler origin.
!byte $0c,$08,$0a,$00,$9e,$32,$30,$36,$34,$00,$00,$00 ; Emit these byte values in order; table and bitmap layout depends on them.

* = $0810 ; Place subsequent bytes at this address; this is an assembler origin.

; STARTUP

; ----------------------------------------------------------------------
; ROUTINE start
; WHAT: Entry from SYS 2064 or replay. Disables IRQs and initialises a new game.
; WHY: Every new game needs known values and a complete display setup before interrupts can use them.
; HOW: Explicit CLD selects binary arithmetic. Requires normal KERNAL, VIC bank 0 and text mode.
; HOW: Does not return. Installs IRQ and enters main_loop. Changes A X Y flags and hardware.
; ----------------------------------------------------------------------
start: ; Name the address of the next emitted byte; a label emits no bytes.
    sei ; Prevent IRQs while hardware and game state are set up
    cld ; Explicitly select binary ADC/SBC for all game arithmetic

    lda #$00 ; Put the literal $00 in A; # selects a value; N/Z reflect it.
    sta BORDER ; Write A to border colour; a store leaves the CPU flags unchanged.
    sta BGCOLOR ; Write A to background colour; a store leaves the CPU flags unchanged.
    jsr clear_screen ; Call clear_screen; push a return address so the callee can return with RTS.
    jsr sound_init ; Set up SID sound effects. Call sound_init; push a return address so the callee can return with RTS.

    lda #$a0 ; Put the literal $a0 in A; # selects a value; N/Z reflect it.
    sta player_x ; Write A to player X low byte; a store leaves the CPU flags unchanged.
    lda #$00 ; Put the literal $00 in A; # selects a value; N/Z reflect it.
    sta player_x_hi ; Write A to player X high byte; a store leaves the CPU flags unchanged.

    lda #$00 ; Put the literal $00 in A; # selects a value; N/Z reflect it.
    sta bullet_active ; Write A to player-shot active flag; a store leaves the CPU flags unchanged.
    sta score ; Write A to binary score low byte; a store leaves the CPU flags unchanged.
    sta score_hi ; Write A to binary score high byte; a store leaves the CPU flags unchanged.
    sta frame_count ; Write A to IRQ frame counter; a store leaves the CPU flags unchanged.
    sta game_over ; Write A to game-over flag; a store leaves the CPU flags unchanged.
    sta irq_phase ; Write A to irq phase; a store leaves the CPU flags unchanged.
    sta hit_edge ; Write A to hit edge; a store leaves the CPU flags unchanged.
    sta wave_number ; Write A to wave number; a store leaves the CPU flags unchanged.
    sta enemy_fire_clock ; Write A to enemy fire clock; a store leaves the CPU flags unchanged.
    sta enemy_fire_index ; Write A to enemy fire index; a store leaves the CPU flags unchanged.
    sta invulnerable ; Write A to invulnerable; a store leaves the CPU flags unchanged.
    sta explosion_timer ; Write A to explosion timer; a store leaves the CPU flags unchanged.
    sta enemy_sound_timer ; Write A to enemy sound timer; a store leaves the CPU flags unchanged.
    lda #8 ; Begin each game at the slowest speed
    sta game_ticks ; Write A to fleet-move countdown; a store leaves the CPU flags unchanged.
    lda #$03 ; Put the literal $03 in A; # selects a value; N/Z reflect it.
    sta lives ; Write A to lives; a store leaves the CPU flags unchanged.
    lda #$00 ; Put the literal $00 in A; # selects a value; N/Z reflect it.
    ldx #$00 ; Put the literal $00 in X; # selects a value; N/Z reflect it.
start_clear_enemy_shots: ; Name the address of the next emitted byte; a label emits no bytes.
    sta enemy_active,x ; Write A to enemy active,x; a store leaves the CPU flags unchanged.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #$03 ; Compare X with a value. Compare X with #$03; set N/Z/C without changing X; C means >= unsigned.
    bne start_clear_enemy_shots ; Branch to start_clear_enemy_shots when Z=0 (nonzero/not equal); otherwise continue in sequence.

    lda #$02 ; Put the literal $02 in A; # selects a value; N/Z reflect it.
    sta direction ; Write A to signed fleet step; a store leaves the CPU flags unchanged.

; Disable sprite expansion and multicolour mode.
    lda #$00 ; Put the literal $00 in A; # selects a value; N/Z reflect it.
    sta $d01c ; Write A to $d01c; a store leaves the CPU flags unchanged.
    sta $d017 ; Write A to $d017; a store leaves the CPU flags unchanged.
    sta $d01d ; Write A to $d01d; a store leaves the CPU flags unchanged.
    sta $d01b ; Write A to $d01b; a store leaves the CPU flags unchanged.
    sta $d010 ; Write A to sprite ninth-X-bit mask; a store leaves the CPU flags unchanged.

; Sprite colours.
    ldx #$00 ; Put the literal $00 in X; # selects a value; N/Z reflect it.
start_sprite_colours: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$05 ; Put the literal $05 in A; # selects a value; N/Z reflect it.
    sta $d027,x ; Write A to $d027,x; a store leaves the CPU flags unchanged.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #$08 ; Compare X with a value. Compare X with #$08; set N/Z/C without changing X; C means >= unsigned.
    bne start_sprite_colours ; Branch to start_sprite_colours when Z=0 (nonzero/not equal); otherwise continue in sequence.

; Sprite pointer table at $07f8-$07ff.
    ldx #$00 ; Put the literal $00 in X; # selects a value; N/Z reflect it.
start_sprite_pointers: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$80 ; Put the literal $80 in A; # selects a value; N/Z reflect it.
    sta $07f8,x ; Write A to $07f8,x; a store leaves the CPU flags unchanged.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #$08 ; Compare X with a value. Compare X with #$08; set N/Z/C without changing X; C means >= unsigned.
    bne start_sprite_pointers ; Branch to start_sprite_pointers when Z=0 (nonzero/not equal); otherwise continue in sequence.

    jsr install_alien_charset ; Call install_alien_charset; push a return address so the callee can return with RTS.
    ldx #$17 ; Put the literal $17 in X; # selects a value; N/Z reflect it.
start_reset_alien_cache: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$00 ; Put the literal $00 in A; # selects a value; N/Z reflect it.
    sta alien_visible,x ; Write A to alien visible,x; a store leaves the CPU flags unchanged.
    dex ; Decrease X by one modulo 256; set N/Z, preserve carry.
    bpl start_reset_alien_cache ; Branch if result is non-negative. Branch to start_reset_alien_cache when N=0 (result bit 7 clear); otherwise continue in sequence.
    jsr init_aliens ; Call init_aliens; push a return address so the callee can return with RTS.
    jsr redraw_aliens ; Call redraw_aliens; push a return address so the callee can return with RTS.
    inc wave_number ; First playable formation is wave 1, not wave 0
    jsr draw_hud ; Call draw_hud; push a return address so the callee can return with RTS.
    jsr update_wave ; Call update_wave; push a return address so the callee can return with RTS.
    jsr update_score ; Call update_score; push a return address so the callee can return with RTS.
    jsr update_lives ; Call update_lives; push a return address so the callee can return with RTS.
    jsr init_shields ; Call init_shields; push a return address so the callee can return with RTS.

; Install raster interrupt vector.
    lda #<raster_irq ; Put the literal <raster_irq in A; # selects a value; N/Z reflect it.
    sta $0314 ; Write A to KERNAL IRQ vector low byte; a store leaves the CPU flags unchanged.
    lda #>raster_irq ; Put the literal >raster_irq in A; # selects a value; N/Z reflect it.
    sta $0315 ; Write A to KERNAL IRQ vector high byte; a store leaves the CPU flags unchanged.

; Acknowledge pending VIC interrupt.
    lda #$01 ; Put the literal $01 in A; # selects a value; N/Z reflect it.
    sta $d019 ; Write A to VIC interrupt status/acknowledge; a store leaves the CPU flags unchanged.

; Start with a raster interrupt at line 0 so the bullet sprite's
; coordinates are programmed before any visible playfield raster line.
    lda $d011 ; Read $d011 into A; update N/Z without changing carry.
    and #$7f ; Keep only bits selected by mask. Keep only bits shared with #$7f; A and N/Z change; carry is preserved.
    sta $d011 ; Write A to $d011; a store leaves the CPU flags unchanged.

    lda #$00 ; Put the literal $00 in A; # selects a value; N/Z reflect it.
    sta $d012 ; Write A to $d012; a store leaves the CPU flags unchanged.

    lda #$01 ; Put the literal $01 in A; # selects a value; N/Z reflect it.
    sta $d01a ; Write A to VIC interrupt enables; a store leaves the CPU flags unchanged.

    cli ; Allow raster IRQs once setup is complete

; MAIN GAME LOOP

; ----------------------------------------------------------------------
; ROUTINE main_loop
; WHAT: Wait for a new frame counter, sample held controls, then update gameplay.
; WHY: A predictable update order makes input, movement, damage and new waves work together.
; HOW: Input runs once after each completed wait; Q ends before other game updates.
; HOW: Calls routines changing A X Y and shared scratch memory; does not return.
; ----------------------------------------------------------------------
main_loop: ; Name the address of the next emitted byte; a label emits no bytes.
    lda frame_count ; Read IRQ frame counter into A; update N/Z without changing carry.
    sta old_frame ; Write A to previously observed frame counter; a store leaves the CPU flags unchanged.

; Wait until the raster IRQ increments frame_count. This limits game
; updates to roughly one update per video frame.
wait_frame: ; Name the address of the next emitted byte; a label emits no bytes.
    lda frame_count ; Read IRQ frame counter into A; update N/Z without changing carry.
    cmp old_frame ; Compare A with old_frame; set N/Z/C without changing A; C means >= unsigned.
    beq wait_frame ; Branch to wait_frame when Z=1 (zero/equal); otherwise continue in sequence.

    jsr read_keyboard ; One physical input sample for this game update.
    lda game_over ; Q can request game over during that input sample.
    beq game_still_running ; Continue gameplay only when no quit was requested.
    jmp end_game ; End before moving other game objects.
game_still_running: ; Name the address of the next emitted byte; a label emits no bytes.
; Speed increases as aliens are destroyed. A countdown gives us
; flexible intervals instead of the old fixed 8-frame bit mask.
; Decrease the timer once per frame; when it reaches zero, move
; the formation and reload the timer from the living alien count.
    dec game_ticks ; Decrease fleet-move countdown by one modulo 256; set N/Z, preserve carry.
    bne skip_alien_move ; Branch to skip_alien_move when Z=0 (nonzero/not equal); otherwise continue in sequence.
    jsr choose_alien_delay ; Call choose_alien_delay; push a return address so the callee can return with RTS.
    sta game_ticks ; Write A to fleet-move countdown; a store leaves the CPU flags unchanged.
    jsr move_aliens ; Call move_aliens; push a return address so the callee can return with RTS.
    jsr redraw_aliens ; Call redraw_aliens; push a return address so the callee can return with RTS.

skip_alien_move: ; Name the address of the next emitted byte; a label emits no bytes.
    jsr update_enemy_shots ; Call update_enemy_shots; push a return address so the callee can return with RTS.
    jsr update_explosion_and_sound ; Call update_explosion_and_sound; push a return address so the callee can return with RTS.
    jsr update_bullet ; Call update_bullet; push a return address so the callee can return with RTS.
; After the final alien is destroyed, start a fresh formation.
    lda aliens_remaining ; Read living-alien count into A; update N/Z without changing carry.
    bne continue_game ; Branch to continue_game when Z=0 (nonzero/not equal); otherwise continue in sequence.
    jsr next_wave ; Call next_wave; push a return address so the callee can return with RTS.
continue_game: ; Name the address of the next emitted byte; a label emits no bytes.
    jmp main_loop ; Continue at main_loop without saving a subroutine return address.

; ALIEN SPEED: fewer survivors = less time between movements
; Input: aliens_remaining (0..24).
; Output: A = number of video frames until the next move.
; A larger number is slower. On a PAL C64, 8 frames is about
; 0.16 seconds; 2 frames is about 0.04 seconds.
; ----------------------------------------------------------------------
; ROUTINE choose_alien_delay
; WHAT: Input aliens_remaining. Output A is 8 6 4 3 or 2 update ticks.
; WHY: The fleet should speed up as it becomes smaller without duplicating movement code.
; HOW: Thresholds 19 13 7 4. Changes A and flags; does not change X or Y.
; HOW: Zero survivors also yields 2, but main_loop starts a new wave.
; ----------------------------------------------------------------------
choose_alien_delay: ; Name the address of the next emitted byte; a label emits no bytes.
    lda aliens_remaining ; Read living-alien count into A; update N/Z without changing carry.
    cmp #19 ; Compare A with #19; set N/Z/C without changing A; C means >= unsigned.
    bcs alien_delay_8 ; 19-24 aliens: every 8 frames. Branch to alien_delay_8 when C=1 (unsigned >= after compare); otherwise continue in sequence.
    cmp #13 ; Compare A with #13; set N/Z/C without changing A; C means >= unsigned.
    bcs alien_delay_6 ; 13-18 aliens: every 6 frames. Branch to alien_delay_6 when C=1 (unsigned >= after compare); otherwise continue in sequence.
    cmp #7 ; Compare A with #7; set N/Z/C without changing A; C means >= unsigned.
    bcs alien_delay_4 ; 7-12 aliens: every 4 frames. Branch to alien_delay_4 when C=1 (unsigned >= after compare); otherwise continue in sequence.
    cmp #4 ; Compare A with #4; set N/Z/C without changing A; C means >= unsigned.
    bcs alien_delay_3 ; 4-6 aliens: every 3 frames. Branch to alien_delay_3 when C=1 (unsigned >= after compare); otherwise continue in sequence.
    lda #2 ; 1-3 aliens: every 2 frames. Put the literal 2 in A; # selects a value; N/Z reflect it.
    rts ; Pull the saved call address and add one; resume after the calling JSR.
alien_delay_8: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #8 ; Put the literal 8 in A; # selects a value; N/Z reflect it.
    rts ; Pull the saved call address and add one; resume after the calling JSR.
alien_delay_6: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #6 ; Put the literal 6 in A; # selects a value; N/Z reflect it.
    rts ; Pull the saved call address and add one; resume after the calling JSR.
alien_delay_4: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #4 ; Put the literal 4 in A; # selects a value; N/Z reflect it.
    rts ; Pull the saved call address and add one; resume after the calling JSR.
alien_delay_3: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #3 ; Put the literal 3 in A; # selects a value; N/Z reflect it.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; KEYBOARD

; WHAT: sample held keys and joystick port 2, then apply one input step.
; WHY: GETIN reports queued characters, not the physical state of held keys.
; HOW: reverse-scan the matrix through CIA1, restoring the normal idle ports.
; A joystick direction takes movement priority; opposing directions cancel.
; With the stick centred, A+D cancel. Fire is accepted from either device.
; ----------------------------------------------------------------------
; ROUTINE read_keyboard
; WHAT: Sample held A/D, Space and Q plus joystick port 2 once per game update.
; WHY: Held movement must follow physical keys and joystick switches without depending on the KERNAL repeat queue.
; HOW: Reverse-scan selected CIA1 columns with IRQs masked, then restore normal idle ports.
; HOW: Joystick directions own movement when deflected; A+D or left+right cancel; either fire source works.
; ----------------------------------------------------------------------
read_keyboard: ; Name the address of the next emitted byte; a label emits no bytes.
    php ; Save flags so the caller's IRQ state can be restored.
    sei ; Keep the KERNAL scan from changing CIA pins mid-read.
    lda #0 ; All direction bits zero means input pins on both ports.
    sta $dc02 ; Port A inputs also let us sample joystick port 2.
    sta $dc03 ; Release all port B keyboard column drivers.
    lda #$ff ; Preload high idle values before enabling any outputs.
    sta $dc00 ; No keyboard row is driven low during the joystick read.
    sta $dc01 ; Port B latch is high while its pins remain inputs.
    lda $dc00 ; Read active-low joystick switches on PA0..PA4.
    sta input_joystick ; Keep this independent sample for priority and firing.
    lda #0 ; No fire or quit action has been requested yet.
    sta input_actions ; Bit 2 means fire; bit 3 means quit.

    lda #$fb ; PB2's latch is zero: this is the A/D keyboard column.
    sta $dc01 ; Set the latch before making that pin an output.
    lda #$04 ; Drive only PB2; leave the other seven columns inputs.
    sta $dc03 ; A held A connects PB2 to PA1; D connects it to PA2.
    lda $dc00 ; Read both direction keys in one physical matrix sample.
    eor #$ff ; Convert active-low pin levels to pressed-is-one bits.
    and #$06 ; Keep PA1 (A) and PA2 (D); discard unrelated pins.
    sta input_keys ; A=$02, D=$04, both=$06, neither=$00.
    lda #0 ; Release the column before changing to another one.
    sta $dc03 ; This avoids driving two selected columns together.

    lda #$ef ; PB4 low selects the column containing Space.
    sta $dc01 ; Unselected columns remain electrically undriven.
    lda #$10 ; Make only PB4 an output.. Put the literal $10 in A; # selects a value; N/Z reflect it.
    sta $dc03 ; Space connects selected PB4 to PA7.
    lda $dc00 ; PA7 reads zero when Space is physically held.
    and #$80 ; Isolate the row shared by Space and Q.
    bne input_no_space ; A high row means Space is released.
    lda #$04 ; Set the logical fire bit rather than firing mid-scan.
    sta input_actions ; Movement will be processed before this fire request.
input_no_space: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #0 ; Disconnect PB4 before selecting Q's column.
    sta $dc03 ; Both CIA ports are now input pins again.
    lda #$bf ; PB6 low selects the column containing Q.
    sta $dc01 ; Prepare the low latch before enabling its output.
    lda #$40 ; Make only PB6 an output.. Put the literal $40 in A; # selects a value; N/Z reflect it.
    sta $dc03 ; Q connects selected PB6 to PA7.. Write A to CIA1 port B direction bits; a store leaves the CPU flags unchanged.
    lda $dc00 ; Read the physical Q key, independently of key repeat.
    and #$80 ; PA7 low means quit is held.. Keep only bits shared with #$80; A and N/Z change; carry is preserved.
    bne input_no_quit ; Skip setting quit when that row is high.
    lda input_actions ; Preserve a fire bit already set by Space.
    ora #$08 ; Add the logical quit bit without clearing other bits.
    sta input_actions ; The quit decision will happen after the scan is safe.
input_no_quit: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #0 ; Restore standard KERNAL idle directions, B as input.
    sta $dc03 ; Stop driving the keyboard columns first.
    lda #$ff ; Idle output latches high to avoid a stuck-low row.
    sta $dc01 ; B remains input; this only prepares its output latch.
    sta $dc00 ; Prepare A's high latch before returning it to output.
    sta $dc02 ; A outputs and B inputs match the normal KERNAL scan.
    plp ; Restore the caller's flags, including the IRQ mask.

    lda input_actions ; Quit takes priority over movement and firing.
    and #$08 ; Test only the Q request recorded during the scan.
    beq input_check_fire ; No quit request: continue with the other actions.
    jmp keyboard_quit ; Reuse the game's game-over request routine.
input_check_fire: ; Name the address of the next emitted byte; a label emits no bytes.
    lda input_joystick ; Fire is bit 4; joystick switches are active low.
    and #$10 ; Zero means the joystick button is pressed.
    bne input_direction ; A high bit leaves the Space request unchanged.
    lda input_actions ; Combine joystick fire with keyboard Space.
    ora #$04 ; Either device may request the single player bullet.
    sta input_actions ; Keep the action until after player movement.
input_direction: ; Name the address of the next emitted byte; a label emits no bytes.
    lda input_joystick ; A deflected joystick owns the movement decision.
    and #$0f ; Test all four direction switches, including up/down.
    cmp #$0f ; All high means the joystick is centred.
    beq input_keyboard ; Only a centred stick allows A/D movement.
    lda input_joystick ; Read the saved sample, not a keyboard-driven pin value.
    and #$0c ; Keep left/right bits; up/down cause no horizontal step.
    cmp #$08 ; Left low and right high requests one left step.
    beq input_left ; Both devices share the same bounded movement routine.
    cmp #$04 ; Right low and left high requests one right step.
    beq input_right ; Both low, or both high, must not pick a direction.
    jmp input_after_move ; Opposing directions and vertical-only input are neutral.
input_keyboard: ; Name the address of the next emitted byte; a label emits no bytes.
    lda input_keys ; Physical key levels captured before restoring the CIA.
    cmp #$02 ; Exactly A, without D, requests a left step.
    beq input_left ; Holding A repeats this decision every game update.
    cmp #$04 ; Exactly D, without A, requests a right step.
    beq input_right ; A+D and neither key both mean no movement.
    jmp input_after_move ; Do not call both movement routines in the same update.
input_left: ; Name the address of the next emitted byte; a label emits no bytes.
    jsr keyboard_left ; Subtract four, subject to the existing left boundary.
    jmp input_after_move ; Movement must not fall through into the right handler.
input_right: ; Name the address of the next emitted byte; a label emits no bytes.
    jsr keyboard_right ; Add four, carrying into the high X byte when needed.
input_after_move: ; Name the address of the next emitted byte; a label emits no bytes.
    lda input_actions ; Move first so a new bullet starts at the new ship X.
    and #$04 ; Test the combined Space/joystick fire request.
    beq keyboard_done ; No fire request: finish this update's input handling.
    jmp fire_bullet ; Existing active-shot check prevents multiple bullets.

keyboard_done: ; Name the address of the next emitted byte; a label emits no bytes.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

keyboard_left: ; Name the address of the next emitted byte; a label emits no bytes.
    lda player_x_hi ; Read player X high byte into A; update N/Z without changing carry.
    bne move_player_left ; Branch to move_player_left when Z=0 (nonzero/not equal); otherwise continue in sequence.
    lda player_x ; Read player X low byte into A; update N/Z without changing carry.
    cmp #$1c ; left edge of visible playfield. Compare A with #$1c; set N/Z/C without changing A; C means >= unsigned.
    bcc keyboard_done ; Jump to keyboard_done if carry is clear (unsigned less-than after CMP)
move_player_left: ; Name the address of the next emitted byte; a label emits no bytes.
    sec ; Set carry so SBC subtracts without an extra borrow
    lda player_x ; Read player X low byte into A; update N/Z without changing carry.
    sbc #$04 ; Subtract #$04 and borrow from A. Subtract #$04 and the incoming borrow from A; C=1 means no borrow.
    sta player_x ; Write A to player X low byte; a store leaves the CPU flags unchanged.
    lda player_x_hi ; Read player X high byte into A; update N/Z without changing carry.
    sbc #$00 ; Subtract #$00 and borrow from A. Subtract #$00 and the incoming borrow from A; C=1 means no borrow.
    sta player_x_hi ; Write A to player X high byte; a store leaves the CPU flags unchanged.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

keyboard_right: ; Name the address of the next emitted byte; a label emits no bytes.
; Ship maximum X = 296 ($0128); 24-pixel sprite stays on screen.
    lda player_x_hi ; Read player X high byte into A; update N/Z without changing carry.
    beq move_player_right ; Branch to move_player_right when Z=1 (zero/equal); otherwise continue in sequence.
    lda player_x ; Read player X low byte into A; update N/Z without changing carry.
    cmp #$28 ; Compare A with #$28; set N/Z/C without changing A; C means >= unsigned.
    bcs keyboard_done ; Jump to keyboard_done if carry is set (unsigned >= after CMP)
move_player_right: ; Name the address of the next emitted byte; a label emits no bytes.
    clc ; Clear carry so ADC starts without adding an extra 1
    lda player_x ; Read player X low byte into A; update N/Z without changing carry.
    adc #$04 ; Add #$04 and carry to A; carry can extend a 16-bit value
    sta player_x ; Write A to player X low byte; a store leaves the CPU flags unchanged.
    lda player_x_hi ; Read player X high byte into A; update N/Z without changing carry.
    adc #$00 ; Add #$00 and carry to A; carry can extend a 16-bit value
    sta player_x_hi ; Write A to player X high byte; a store leaves the CPU flags unchanged.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

keyboard_fire: ; Name the address of the next emitted byte; a label emits no bytes.
    jmp fire_bullet ; Continue at fire_bullet without saving a subroutine return address.

keyboard_quit: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$01 ; Put the literal $01 in A; # selects a value; N/Z reflect it.
    sta game_over ; Write A to game-over flag; a store leaves the CPU flags unchanged.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; FIRE AND UPDATE BULLET

; ----------------------------------------------------------------------
; ROUTINE fire_bullet
; WHAT: If bullet_active is zero, copies player X and starts one shot at Y=$D0.
; WHY: One active-shot flag prevents repeated keypresses from overwriting a bullet already in flight.
; HOW: Output bullet_active=1 on successful spawn. Uses voice 1 for sound.
; HOW: Changes A and flags. Existing active shot prevents another spawn.
; ----------------------------------------------------------------------
fire_bullet: ; Name the address of the next emitted byte; a label emits no bytes.
; Only allow one player bullet on screen at a time.
    lda bullet_active ; Read player-shot active flag into A; update N/Z without changing carry.
    bne fire_done ; Don't fire if a bullet is already active

    lda player_x ; Read player X low byte into A; update N/Z without changing carry.
    sta bullet_x ; Write A to player shot X low byte; a store leaves the CPU flags unchanged.
    lda player_x_hi ; Read player X high byte into A; update N/Z without changing carry.
    sta bullet_x_hi ; Write A to player shot X high byte; a store leaves the CPU flags unchanged.

    lda #$d0 ; Put the literal $d0 in A; # selects a value; N/Z reflect it.
    sta bullet_y ; Write A to player shot Y; a store leaves the CPU flags unchanged.

    lda #$01 ; Put the literal $01 in A; # selects a value; N/Z reflect it.
    sta bullet_active ; Write A to player-shot active flag; a store leaves the CPU flags unchanged.

    jsr sound_fire ; Play a short laser sound. Call sound_fire; push a return address so the callee can return with RTS.

fire_done: ; Name the address of the next emitted byte; a label emits no bytes.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; ----------------------------------------------------------------------
; ROUTINE update_bullet
; WHAT: Moves active bullet up four pixels; removes it above the top limit.
; WHY: A bullet needs both movement and removal rules so it cannot remain active beyond the playfield.
; HOW: Then checks shield sample point before alien rectangle tests.
; HOW: Changes A X Y flags and scratch state via callees. At most one alien hit per shot.
; ----------------------------------------------------------------------
update_bullet: ; Name the address of the next emitted byte; a label emits no bytes.
    lda bullet_active ; Read player-shot active flag into A; update N/Z without changing carry.
    beq bullet_update_done ; Nothing to move if no bullet is active

; Move upward: on the C64, smaller sprite Y values are higher on screen.
    lda bullet_y ; Read player shot Y into A; update N/Z without changing carry.
    sec ; Set carry so SBC subtracts without an extra borrow
    sbc #$04 ; Subtract #$04 and borrow from A. Subtract #$04 and the incoming borrow from A; C=1 means no borrow.
    sta bullet_y ; Write A to player shot Y; a store leaves the CPU flags unchanged.

; Stop the bullet once it has reached the top of the visible play area.
; Clear bullet_active so the IRQ hides the sprite and another shot can fire.
    cmp #$08 ; Compare A with #$08; set N/Z/C without changing A; C means >= unsigned.
    bcs bullet_check_collision ; Jump to bullet_check_collision if carry is set (unsigned >= after CMP)
    lda #$00 ; Put the literal $00 in A; # selects a value; N/Z reflect it.
    sta bullet_active ; Write A to player-shot active flag; a store leaves the CPU flags unchanged.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

bullet_update_done: ; Name the address of the next emitted byte; a label emits no bytes.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; ----------------------------------------------------------------------
; ROUTINE bullet_check_collision
; WHAT: Input active bullet position. Tests shields first at X+11,Y+9.
; WHY: The program must identify a particular character alien and let a shield absorb the shot first.
; HOW: Alien X test samples X+11 against cached displayed width 16.
; HOW: Alien Y test uses bullet offsets +4 through +8 against displayed height 8.
; ----------------------------------------------------------------------
bullet_check_collision: ; Name the address of the next emitted byte; a label emits no bytes.
; Shield absorbs a player's shot before it can hit an alien.
    clc ; Clear carry so ADC starts without adding an extra 1
    lda bullet_x ; Read player shot X low byte into A; update N/Z without changing carry.
    adc #11 ; Add #11 and carry to A; carry can extend a 16-bit value
    sta shield_shot_x ; Write A to shield shot x; a store leaves the CPU flags unchanged.
    lda bullet_x_hi ; Read player shot X high byte into A; update N/Z without changing carry.
    adc #0 ; Add #0 and carry to A; carry can extend a 16-bit value
    sta shield_shot_hi ; Write A to shield shot hi; a store leaves the CPU flags unchanged.
    lda bullet_y ; Read player shot Y into A; update N/Z without changing carry.
    clc ; Clear carry so ADC starts without adding an extra 1
    adc #$09 ; Add #$09 and carry to A; carry can extend a 16-bit value
    sta shield_shot_y ; Write A to shield shot y; a store leaves the CPU flags unchanged.
    jsr shield_test_shot ; Call shield_test_shot; push a return address so the callee can return with RTS.
    bcc bullet_check_aliens ; Jump to bullet_check_aliens if carry is clear (unsigned less-than after CMP)
    lda #0 ; Put the literal 0 in A; # selects a value; N/Z reflect it.
    sta bullet_active ; Write A to player-shot active flag; a store leaves the CPU flags unchanged.
    rts ; Pull the saved call address and add one; resume after the calling JSR.
bullet_check_aliens: ; Name the address of the next emitted byte; a label emits no bytes.
; Collision uses the EXACT cached positions from render_aliens.
; Bullet sprite's first lit pixel is at Y+4, X+11.
; Sweep its leading edge over the 4 pixels moved this tick.
    clc ; Clear carry so ADC starts without adding an extra 1
    lda bullet_x ; Read player shot X low byte into A; update N/Z without changing carry.
    adc #11 ; Add #11 and carry to A; carry can extend a 16-bit value
    sta collision_bullet_lo ; Write A to collision bullet lo; a store leaves the CPU flags unchanged.
    lda bullet_x_hi ; Read player shot X high byte into A; update N/Z without changing carry.
    adc #0 ; Add #0 and carry to A; carry can extend a 16-bit value
    sta collision_bullet_hi ; Write A to collision bullet hi; a store leaves the CPU flags unchanged.
    ldx #23 ; Put the literal 23 in X; # selects a value; N/Z reflect it.
collision_loop: ; Name the address of the next emitted byte; a label emits no bytes.
    lda alien_alive,x ; Read alien alive,x at the indexed element into A; update N/Z, preserve carry.
    beq collision_next_jump ; Branch to collision_next_jump when Z=1 (zero/equal); otherwise continue in sequence.
    lda alien_visible,x ; Read alien visible,x at the indexed element into A; update N/Z, preserve carry.
    beq collision_next_jump ; Branch to collision_next_jump when Z=1 (zero/equal); otherwise continue in sequence.

; Compare bullet centre to the actual drawn 16-pixel-wide image.
    sec ; Set carry so SBC subtracts without an extra borrow
    lda collision_bullet_lo ; Read collision bullet lo into A; update N/Z without changing carry.
    sbc alien_draw_x,x ; Subtract alien_draw_x,x and borrow from A
    sta collision_delta ; Write A to collision delta; a store leaves the CPU flags unchanged.
    lda collision_bullet_hi ; Read collision bullet hi into A; update N/Z without changing carry.
    sbc alien_draw_x_hi,x ; Subtract alien_draw_x_hi,x and borrow from A
    bne collision_next_jump ; Branch to collision_next_jump when Z=0 (nonzero/not equal); otherwise continue in sequence.
    lda collision_delta ; Read collision delta into A; update N/Z without changing carry.
    cmp #16 ; Compare A with #16; set N/Z/C without changing A; C means >= unsigned.
    bcs collision_next_jump ; Jump to collision_next_jump if carry is set (unsigned >= after CMP)

; A rising bullet sweeps from old tip Y+8 to new tip Y+4.
; It hits when the swept interval intersects drawn row Y..Y+7.
    lda bullet_y ; Read player shot Y into A; update N/Z without changing carry.
    clc ; Clear carry so ADC starts without adding an extra 1
    adc #4 ; Add #4 and carry to A; carry can extend a 16-bit value
    sta collision_top ; Write A to collision top; a store leaves the CPU flags unchanged.
    lda alien_draw_y,x ; Read alien draw y,x at the indexed element into A; update N/Z, preserve carry.
    clc ; Clear carry so ADC starts without adding an extra 1
    adc #7 ; Add #7 and carry to A; carry can extend a 16-bit value
    cmp collision_top ; Compare A with collision_top; set N/Z/C without changing A; C means >= unsigned.
    bcc collision_next_jump ; Jump to collision_next_jump if carry is clear (unsigned less-than after CMP)
    lda bullet_y ; Read player shot Y into A; update N/Z without changing carry.
    clc ; Clear carry so ADC starts without adding an extra 1
    adc #8 ; Add #8 and carry to A; carry can extend a 16-bit value
    cmp alien_draw_y,x ; Compare A with alien_draw_y,x; set N/Z/C without changing A; C means >= unsigned.
    bcc collision_next_jump ; Jump to collision_next_jump if carry is clear (unsigned less-than after CMP)
    jmp collision_hit ; Continue at collision_hit without saving a subroutine return address.
collision_next_jump: ; Name the address of the next emitted byte; a label emits no bytes.
    dex ; Decrease X by one modulo 256; set N/Z, preserve carry.
    bmi collision_scan_done ; Branch if result is negative. Branch to collision_scan_done when N=1 (result bit 7 set); otherwise continue in sequence.
    jmp collision_loop ; Continue at collision_loop without saving a subroutine return address.

collision_hit: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$00 ; Put the literal $00 in A; # selects a value; N/Z reflect it.
    sta alien_alive,x ; Write A to alien alive,x; a store leaves the CPU flags unchanged.
    sta bullet_active ; Write A to player-shot active flag; a store leaves the CPU flags unchanged.
    dec aliens_remaining ; Decrease living-alien count by one modulo 256; set N/Z, preserve carry.
    jsr redraw_aliens ; Call redraw_aliens; push a return address so the callee can return with RTS.
    inc score ; Increase binary score low byte by one modulo 256; set N/Z, preserve carry.
    bne score_incremented ; Branch to score_incremented when Z=0 (nonzero/not equal); otherwise continue in sequence.
    inc score_hi ; Increase binary score high byte by one modulo 256; set N/Z, preserve carry.
score_incremented: ; Name the address of the next emitted byte; a label emits no bytes.
    lda score_hi ; Read binary score high byte into A; update N/Z without changing carry.
    cmp #$03 ; Compare A with #$03; set N/Z/C without changing A; C means >= unsigned.
    bcc score_not_capped ; Jump to score_not_capped if carry is clear (unsigned less-than after CMP)
    bne cap_score ; Branch to cap_score when Z=0 (nonzero/not equal); otherwise continue in sequence.
    lda score ; Read binary score low byte into A; update N/Z without changing carry.
    cmp #$e8 ; Compare A with #$e8; set N/Z/C without changing A; C means >= unsigned.
    bcc score_not_capped ; Jump to score_not_capped if carry is clear (unsigned less-than after CMP)
cap_score: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$e8 ; Put the literal $e8 in A; # selects a value; N/Z reflect it.
    sta score ; Write A to binary score low byte; a store leaves the CPU flags unchanged.
    lda #$03 ; Put the literal $03 in A; # selects a value; N/Z reflect it.
    sta score_hi ; Write A to binary score high byte; a store leaves the CPU flags unchanged.
score_not_capped: ; Name the address of the next emitted byte; a label emits no bytes.
    jsr update_score ; Call update_score; push a return address so the callee can return with RTS.
    jsr sound_hit ; Call sound_hit; push a return address so the callee can return with RTS.
    rts ; Pull the saved call address and add one; resume after the calling JSR.
collision_scan_done: ; Name the address of the next emitted byte; a label emits no bytes.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; ENEMY SHOTS: 3 physical sprites, independently falling.
; One random-ish living alien launches a bolt periodically.
; The frame counter and changing selection index vary the shooter.
; ----------------------------------------------------------------------
; ROUTINE update_enemy_shots
; WHAT: Three slots move down 3 pixels; shield test precedes player hit test.
; WHY: A fixed three-slot array bounds the work and gives each enemy shot its own state.
; HOW: Decrements invulnerable; attempts a spawn each 64 updates if a slot is free.
; HOW: Changes A X Y flags and shared scratch state. Selection is deterministic.
; ----------------------------------------------------------------------
update_enemy_shots: ; Name the address of the next emitted byte; a label emits no bytes.
    lda invulnerable ; Read invulnerable into A; update N/Z without changing carry.
    beq enemy_invuln_done ; Branch to enemy_invuln_done when Z=1 (zero/equal); otherwise continue in sequence.
    dec invulnerable ; Decrease invulnerable by one modulo 256; set N/Z, preserve carry.
enemy_invuln_done: ; Name the address of the next emitted byte; a label emits no bytes.
    ldx #0 ; Put the literal 0 in X; # selects a value; N/Z reflect it.
enemy_update_loop: ; Name the address of the next emitted byte; a label emits no bytes.
    lda enemy_active,x ; Read enemy active,x at the indexed element into A; update N/Z, preserve carry.
    bne enemy_shot_active ; Branch to enemy_shot_active when Z=0 (nonzero/not equal); otherwise continue in sequence.
    jmp enemy_update_next ; Continue at enemy_update_next without saving a subroutine return address.
enemy_shot_active: ; Name the address of the next emitted byte; a label emits no bytes.
    clc ; Clear carry so ADC starts without adding an extra 1
    lda enemy_y,x ; Read enemy y,x at the indexed element into A; update N/Z, preserve carry.
    adc #3 ; Add #3 and carry to A; carry can extend a 16-bit value
    sta enemy_y,x ; Write A to enemy y,x; a store leaves the CPU flags unchanged.
    cmp #$f0 ; Keep shots alive through player at Y=220
    bcc enemy_check_ship ; Jump to enemy_check_ship if carry is clear (unsigned less-than after CMP)
    lda #0 ; Put the literal 0 in A; # selects a value; N/Z reflect it.
    sta enemy_active,x ; Write A to enemy active,x; a store leaves the CPU flags unchanged.
    jmp enemy_update_next ; Continue at enemy_update_next without saving a subroutine return address.
enemy_check_ship: ; Name the address of the next emitted byte; a label emits no bytes.
; Shields absorb incoming alien bolts before they hit the ship.
    txa ; Copy X to A. Copy X to A; N/Z reflect the copied byte.
    pha ; Push A onto stack. Push A on the hardware stack; balance this save with a later PLA.
    clc ; Clear carry so ADC starts without adding an extra 1
    lda enemy_x,x ; Read enemy x,x at the indexed element into A; update N/Z, preserve carry.
    adc #11 ; Add #11 and carry to A; carry can extend a 16-bit value
    sta shield_shot_x ; Write A to shield shot x; a store leaves the CPU flags unchanged.
    lda enemy_x_hi,x ; Read enemy x hi,x at the indexed element into A; update N/Z, preserve carry.
    adc #0 ; Add #0 and carry to A; carry can extend a 16-bit value
    sta shield_shot_hi ; Write A to shield shot hi; a store leaves the CPU flags unchanged.
    lda enemy_y,x ; Read enemy y,x at the indexed element into A; update N/Z, preserve carry.
    clc ; Clear carry so ADC starts without adding an extra 1
    adc #$0b ; Add #$0b and carry to A; carry can extend a 16-bit value
    sta shield_shot_y ; Write A to shield shot y; a store leaves the CPU flags unchanged.
    jsr shield_test_shot ; Call shield_test_shot; push a return address so the callee can return with RTS.
    pla ; Pull A from stack. Pull a byte into A; update N/Z but leave carry unchanged.
    tax ; Copy A to X. Copy A to X; N/Z reflect the copied byte.
    bcc enemy_check_ship_actual ; Jump to enemy_check_ship_actual if carry is clear (unsigned less-than after CMP)
    lda #0 ; Put the literal 0 in A; # selects a value; N/Z reflect it.
    sta enemy_active,x ; Write A to enemy active,x; a store leaves the CPU flags unchanged.
    jmp enemy_update_next ; Continue at enemy_update_next without saving a subroutine return address.
enemy_check_ship_actual: ; Name the address of the next emitted byte; a label emits no bytes.
; Test bolt visible pixels against ship's actual sprite pixels.
; Ship sprite Y=220; bolt pixels extend from Y+2 to Y+12.
    lda invulnerable ; Read invulnerable into A; update N/Z without changing carry.
    bne enemy_update_next ; Branch to enemy_update_next when Z=0 (nonzero/not equal); otherwise continue in sequence.
    lda enemy_y,x ; Read enemy y,x at the indexed element into A; update N/Z, preserve carry.
    clc ; Clear carry so ADC starts without adding an extra 1
    adc #12 ; Add #12 and carry to A; carry can extend a 16-bit value
    cmp #220 ; Compare A with #220; set N/Z/C without changing A; C means >= unsigned.
    bcc enemy_update_next ; Jump to enemy_update_next if carry is clear (unsigned less-than after CMP)
    lda enemy_y,x ; Read enemy y,x at the indexed element into A; update N/Z, preserve carry.
    clc ; Clear carry so ADC starts without adding an extra 1
    adc #2 ; Add #2 and carry to A; carry can extend a 16-bit value
    cmp #241 ; Compare A with #241; set N/Z/C without changing A; C means >= unsigned.
    bcs enemy_update_next ; Jump to enemy_update_next if carry is set (unsigned >= after CMP)
; Shot centre = sprite X + 11, ship visible range X+3..X+22.
    clc ; Clear carry so ADC starts without adding an extra 1
    lda enemy_x,x ; Read enemy x,x at the indexed element into A; update N/Z, preserve carry.
    adc #11 ; Add #11 and carry to A; carry can extend a 16-bit value
    sta enemy_delta ; Write A to enemy delta; a store leaves the CPU flags unchanged.
    lda enemy_x_hi,x ; Read enemy x hi,x at the indexed element into A; update N/Z, preserve carry.
    adc #0 ; Add #0 and carry to A; carry can extend a 16-bit value
    sta enemy_delta_hi ; Write A to enemy delta hi; a store leaves the CPU flags unchanged.
    sec ; Set carry so SBC subtracts without an extra borrow
    lda enemy_delta ; Read enemy delta into A; update N/Z without changing carry.
    sbc player_x ; Subtract player_x and borrow from A
    sta enemy_delta ; Write A to enemy delta; a store leaves the CPU flags unchanged.
    lda enemy_delta_hi ; Read enemy delta hi into A; update N/Z without changing carry.
    sbc player_x_hi ; Subtract player_x_hi and borrow from A
    bne enemy_update_next ; Branch to enemy_update_next when Z=0 (nonzero/not equal); otherwise continue in sequence.
    lda enemy_delta ; Read enemy delta into A; update N/Z without changing carry.
    cmp #1 ; Compare A with #1; set N/Z/C without changing A; C means >= unsigned.
    bcc enemy_update_next ; Jump to enemy_update_next if carry is clear (unsigned less-than after CMP)
    cmp #24 ; Compare A with #24; set N/Z/C without changing A; C means >= unsigned.
    bcs enemy_update_next ; Jump to enemy_update_next if carry is set (unsigned >= after CMP)
enemy_ship_hit: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #0 ; Put the literal 0 in A; # selects a value; N/Z reflect it.
    sta enemy_active,x ; Write A to enemy active,x; a store leaves the CPU flags unchanged.
    txa ; Copy X to A. Copy X to A; N/Z reflect the copied byte.
    pha ; Push A onto stack. Push A on the hardware stack; balance this save with a later PLA.
    jsr lose_life ; Call lose_life; push a return address so the callee can return with RTS.
    pla ; Pull A from stack. Pull a byte into A; update N/Z but leave carry unchanged.
    tax ; Copy A to X. Copy A to X; N/Z reflect the copied byte.
enemy_update_next: ; Name the address of the next emitted byte; a label emits no bytes.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #3 ; Compare X with a value. Compare X with #3; set N/Z/C without changing X; C means >= unsigned.
    beq enemy_updates_complete ; Branch to enemy_updates_complete when Z=1 (zero/equal); otherwise continue in sequence.
    jmp enemy_update_loop ; Continue at enemy_update_loop without saving a subroutine return address.
enemy_updates_complete: ; Name the address of the next emitted byte; a label emits no bytes.

; Launch once every 64 frames, if a slot is available.
    inc enemy_fire_clock ; Increase enemy fire clock by one modulo 256; set N/Z, preserve carry.
    lda enemy_fire_clock ; Read enemy fire clock into A; update N/Z without changing carry.
    and #$3f ; Keep only bits selected by mask. Keep only bits shared with #$3f; A and N/Z change; carry is preserved.
    bne enemy_update_done ; Branch to enemy_update_done when Z=0 (nonzero/not equal); otherwise continue in sequence.
    ldx #0 ; Put the literal 0 in X; # selects a value; N/Z reflect it.
enemy_find_slot: ; Name the address of the next emitted byte; a label emits no bytes.
    lda enemy_active,x ; Read enemy active,x at the indexed element into A; update N/Z, preserve carry.
    beq enemy_slot_found ; Branch to enemy_slot_found when Z=1 (zero/equal); otherwise continue in sequence.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #3 ; Compare X with a value. Compare X with #3; set N/Z/C without changing X; C means >= unsigned.
    bne enemy_find_slot ; Branch to enemy_find_slot when Z=0 (nonzero/not equal); otherwise continue in sequence.
    rts ; Pull the saved call address and add one; resume after the calling JSR.
enemy_slot_found: ; Name the address of the next emitted byte; a label emits no bytes.
    stx enemy_slot ; Store index register X. Write X to enemy slot; a store leaves the CPU flags unchanged.
; Choose among 24 aliens, skip destroyed ones.
; Changing frame timing makes shots less predictable.
    lda enemy_fire_index ; Read enemy fire index into A; update N/Z without changing carry.
    clc ; Clear carry so ADC starts without adding an extra 1
    adc frame_count ; Add frame_count and carry to A; carry can extend a 16-bit value
    and #$1f ; Keep only bits selected by mask. Keep only bits shared with #$1f; A and N/Z change; carry is preserved.
    cmp #24 ; Compare A with #24; set N/Z/C without changing A; C means >= unsigned.
    bcc enemy_index_ok ; Jump to enemy_index_ok if carry is clear (unsigned less-than after CMP)
    sec ; Set carry so SBC subtracts without an extra borrow
    sbc #24 ; Subtract #24 and borrow from A. Subtract #24 and the incoming borrow from A; C=1 means no borrow.
enemy_index_ok: ; Name the address of the next emitted byte; a label emits no bytes.
    tay ; Copy A to Y. Copy A to Y; N/Z reflect the copied byte.
    ldx #24 ; Put the literal 24 in X; # selects a value; N/Z reflect it.
enemy_find_living: ; Name the address of the next emitted byte; a label emits no bytes.
    lda alien_alive,y ; Read alien alive,y at the indexed element into A; update N/Z, preserve carry.
    bne enemy_shooter_found ; Branch to enemy_shooter_found when Z=0 (nonzero/not equal); otherwise continue in sequence.
    iny ; Increase Y by one modulo 256; set N/Z, preserve carry.
    cpy #24 ; Compare Y with a value. Compare Y with #24; set N/Z/C without changing Y; C means >= unsigned.
    bne enemy_find_continue ; Branch to enemy_find_continue when Z=0 (nonzero/not equal); otherwise continue in sequence.
    ldy #0 ; Put the literal 0 in Y; # selects a value; N/Z reflect it.
enemy_find_continue: ; Name the address of the next emitted byte; a label emits no bytes.
    dex ; Decrease X by one modulo 256; set N/Z, preserve carry.
    bne enemy_find_living ; Branch to enemy_find_living when Z=0 (nonzero/not equal); otherwise continue in sequence.
    rts ; Pull the saved call address and add one; resume after the calling JSR.
enemy_shooter_found: ; Name the address of the next emitted byte; a label emits no bytes.
    sty enemy_fire_index ; Store index register Y. Write Y to enemy fire index; a store leaves the CPU flags unchanged.
    inc enemy_fire_index ; Increase enemy fire index by one modulo 256; set N/Z, preserve carry.
    ldx enemy_slot ; Read enemy slot into X; update N/Z without changing carry.
    lda alien_draw_x,y ; Fire from the visible alien, not a snapped approximation.
    sta enemy_x,x ; Write A to enemy x,x; a store leaves the CPU flags unchanged.
    lda alien_draw_x_hi,y ; Read alien draw x hi,y at the indexed element into A; update N/Z, preserve carry.
    sta enemy_x_hi,x ; Write A to enemy x hi,x; a store leaves the CPU flags unchanged.
    lda alien_draw_y,y ; Read alien draw y,y at the indexed element into A; update N/Z, preserve carry.
    clc ; Clear carry so ADC starts without adding an extra 1
    adc #$0b ; Add #$0b and carry to A; carry can extend a 16-bit value
    sta enemy_y,x ; Write A to enemy y,x; a store leaves the CPU flags unchanged.
    lda #1 ; Put the literal 1 in A; # selects a value; N/Z reflect it.
    sta enemy_active,x ; Write A to enemy active,x; a store leaves the CPU flags unchanged.
    jsr sound_enemy_fire ; Call sound_enemy_fire; push a return address so the callee can return with RTS.
enemy_update_done: ; Name the address of the next emitted byte; a label emits no bytes.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; ----------------------------------------------------------------------
; ROUTINE lose_life
; WHAT: No effect if protected or already at zero lives. Otherwise decrements lives.
; WHY: Centralising damage prevents several contacts in one update from taking several lives.
; HOW: Starts protection counter 90 and explosion counter 26; updates HUD and sound.
; HOW: Sets game_over at zero. Changes A X and flags through callees.
; ----------------------------------------------------------------------
lose_life: ; Name the address of the next emitted byte; a label emits no bytes.
; One hit = one life; temporary invulnerability prevents rapid loss.
    lda invulnerable ; Read invulnerable into A; update N/Z without changing carry.
    bne lose_life_done ; Branch to lose_life_done when Z=0 (nonzero/not equal); otherwise continue in sequence.
    lda lives ; Read lives into A; update N/Z without changing carry.
    beq lose_life_done ; Branch to lose_life_done when Z=1 (zero/equal); otherwise continue in sequence.
    dec lives ; Decrease lives by one modulo 256; set N/Z, preserve carry.
    lda #90 ; Put the literal 90 in A; # selects a value; N/Z reflect it.
    sta invulnerable ; Write A to invulnerable; a store leaves the CPU flags unchanged.
    lda #26 ; Put the literal 26 in A; # selects a value; N/Z reflect it.
    sta explosion_timer ; Write A to explosion timer; a store leaves the CPU flags unchanged.
    jsr update_lives ; Call update_lives; push a return address so the callee can return with RTS.
    jsr sound_player_hit ; Call sound_player_hit; push a return address so the callee can return with RTS.
    lda lives ; Read lives into A; update N/Z without changing carry.
    bne lose_life_done ; Branch to lose_life_done when Z=0 (nonzero/not equal); otherwise continue in sequence.
    lda #1 ; Put the literal 1 in A; # selects a value; N/Z reflect it.
    sta game_over ; Write A to game-over flag; a store leaves the CPU flags unchanged.
lose_life_done: ; Name the address of the next emitted byte; a label emits no bytes.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; Explosion display uses sprite 0 with pointer $84 ($2100).
; The 26-frame countdown runs outside the IRQ, once per game frame.
; ----------------------------------------------------------------------
; ROUTINE update_explosion_and_sound
; WHAT: Decrements active explosion and enemy voice release counters.
; WHY: Counters let an effect finish later while the rest of the game keeps running.
; HOW: When enemy_sound_timer becomes zero, clears voice 2 gate with $D40B=$80.
; HOW: Changes A and flags. Counts game updates, not guaranteed wall-clock durations.
; ----------------------------------------------------------------------
update_explosion_and_sound: ; Name the address of the next emitted byte; a label emits no bytes.
    lda explosion_timer ; Read explosion timer into A; update N/Z without changing carry.
    beq explosion_timer_done ; Branch to explosion_timer_done when Z=1 (zero/equal); otherwise continue in sequence.
    dec explosion_timer ; Decrease explosion timer by one modulo 256; set N/Z, preserve carry.
explosion_timer_done: ; Name the address of the next emitted byte; a label emits no bytes.
    lda enemy_sound_timer ; Read enemy sound timer into A; update N/Z without changing carry.
    beq enemy_sound_done ; Branch to enemy_sound_done when Z=1 (zero/equal); otherwise continue in sequence.
    dec enemy_sound_timer ; Decrease enemy sound timer by one modulo 256; set N/Z, preserve carry.
    bne enemy_sound_done ; Branch to enemy_sound_done when Z=0 (nonzero/not equal); otherwise continue in sequence.
    lda #$80 ; Voice 2: noise waveform, gate off. Put the literal $80 in A; # selects a value; N/Z reflect it.
    sta $d40b ; Write A to $d40b; a store leaves the CPU flags unchanged.
enemy_sound_done: ; Name the address of the next emitted byte; a label emits no bytes.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; ----------------------------------------------------------------------
; ROUTINE update_lives
; WHAT: Reads lives. Writes label at row 0 columns 26..32 and digit at 33.
; WHY: Changing the stored life count does not automatically change its displayed screen digit.
; HOW: Known layout defect: overlaps wave label columns 30..34.
; HOW: Changes A X flags. Matching colour stores use white.
; ----------------------------------------------------------------------
update_lives: ; Name the address of the next emitted byte; a label emits no bytes.
; HUD row 0, columns 26-33: "LIVES: 3".
    ldx #0 ; Put the literal 0 in X; # selects a value; N/Z reflect it.
lives_label_loop: ; Name the address of the next emitted byte; a label emits no bytes.
    lda lives_text,x ; Read lives text,x at the indexed element into A; update N/Z, preserve carry.
    sta SCREEN+26,x ; Write A to SCREEN+26,x; a store leaves the CPU flags unchanged.
    lda #$01 ; Put the literal $01 in A; # selects a value; N/Z reflect it.
    sta COLOR+26,x ; Write A to COLOR+26,x; a store leaves the CPU flags unchanged.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #7 ; Compare X with a value. Compare X with #7; set N/Z/C without changing X; C means >= unsigned.
    bne lives_label_loop ; Branch to lives_label_loop when Z=0 (nonzero/not equal); otherwise continue in sequence.
    lda lives ; Read lives into A; update N/Z without changing carry.
    clc ; Clear carry so ADC starts without adding an extra 1
    adc #$30 ; Add #$30 and carry to A; carry can extend a 16-bit value
    sta SCREEN+33 ; Write A to SCREEN+33; a store leaves the CPU flags unchanged.
    lda #$01 ; Put the literal $01 in A; # selects a value; N/Z reflect it.
    sta COLOR+33 ; Write A to COLOR+33; a store leaves the CPU flags unchanged.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; ----------------------------------------------------------------------
; ROUTINE init_aliens
; WHAT: Initialises 24 living aliens as 3 rows of 8, X=32+24*column.
; WHY: The game needs a reusable way to create the same formation for startup, waves and invasion recovery.
; HOW: Logical Y starts 64 94 124; renderer quantises the displayed Y.
; HOW: Changes A X Y flags and temporary bytes. Does not increment wave_number.
; ----------------------------------------------------------------------
init_aliens: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #24 ; Put the literal 24 in A; # selects a value; N/Z reflect it.
    sta aliens_remaining ; Write A to living-alien count; a store leaves the CPU flags unchanged.
; X is the alien index (0-23); its low three bits select a column.
    ldx #$00 ; Put the literal $00 in X; # selects a value; N/Z reflect it.

init_alien_loop: ; Name the address of the next emitted byte; a label emits no bytes.
    txa ; Copy X to A. Copy X to A; N/Z reflect the copied byte.
    and #$07 ; Keep only bits selected by mask. Keep only bits shared with #$07; A and N/Z change; carry is preserved.
    sta temp_col ; Write A to temp col; a store leaves the CPU flags unchanged.

; X coordinate = 32 + column * 24.
; Three-cell slots prevent neighbouring shifted pictures overwriting
; each other. All eight aliens share the same horizontal pixel phase.
    lda temp_col ; Read temp col into A; update N/Z without changing carry.
    asl ; Shift bits left (multiply by 2). Shift left with zero entering bit 0; old bit 7 goes to carry; update N/Z.
    asl ; Shift bits left (multiply by 2). Shift left with zero entering bit 0; old bit 7 goes to carry; update N/Z.
    asl ; column * 8, added to column * 16 below.
    sta temp_x ; Write A to temp x; a store leaves the CPU flags unchanged.

    lda temp_col ; Read temp col into A; update N/Z without changing carry.
    asl ; Shift bits left (multiply by 2). Shift left with zero entering bit 0; old bit 7 goes to carry; update N/Z.
    asl ; Shift bits left (multiply by 2). Shift left with zero entering bit 0; old bit 7 goes to carry; update N/Z.
    asl ; Shift bits left (multiply by 2). Shift left with zero entering bit 0; old bit 7 goes to carry; update N/Z.
    asl ; Shift bits left (multiply by 2). Shift left with zero entering bit 0; old bit 7 goes to carry; update N/Z.
    clc ; Clear carry so ADC starts without adding an extra 1
    adc temp_x ; Add temp_x and carry to A; carry can extend a 16-bit value
    clc ; Clear carry so ADC starts without adding an extra 1
    adc #$20 ; Add #$20 and carry to A; carry can extend a 16-bit value
    sta alien_x,x ; Write A to alien x,x; a store leaves the CPU flags unchanged.
    lda #$00 ; Put the literal $00 in A; # selects a value; N/Z reflect it.
    sta alien_x_hi,x ; Write A to alien x hi,x; a store leaves the CPU flags unchanged.

; Y coordinate from row table.
    txa ; Copy X to A. Copy X to A; N/Z reflect the copied byte.
    lsr ; Shift bits right (divide by 2). Shift right with zero entering bit 7; old bit 0 goes to carry; update N/Z.
    lsr ; Shift bits right (divide by 2). Shift right with zero entering bit 7; old bit 0 goes to carry; update N/Z.
    lsr ; Shift bits right (divide by 2). Shift right with zero entering bit 7; old bit 0 goes to carry; update N/Z.
    tay ; Copy A to Y. Copy A to Y; N/Z reflect the copied byte.

    lda alien_row_y,y ; Read alien row y,y at the indexed element into A; update N/Z, preserve carry.
    sta alien_y,x ; Write A to alien y,x; a store leaves the CPU flags unchanged.

    lda #$01 ; Put the literal $01 in A; # selects a value; N/Z reflect it.
    sta alien_alive,x ; Write A to alien alive,x; a store leaves the CPU flags unchanged.

    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #$18 ; Compare X with a value. Compare X with #$18; set N/Z/C without changing X; C means >= unsigned.
    bne init_alien_loop ; Branch to init_alien_loop when Z=0 (nonzero/not equal); otherwise continue in sequence.

    rts ; Pull the saved call address and add one; resume after the calling JSR.

; Each wave resets the formation without resetting the score or ship.
; ----------------------------------------------------------------------
; ROUTINE next_wave
; WHAT: Increments byte wave_number, clears shots, recreates fleet and resets delay.
; WHY: A completed formation must be replaced while preserving the player's score, lives and shield damage.
; HOW: Preserves score lives and shield health. Wave 255 wraps to 0.
; HOW: Changes A X Y flags via callees. Does not call init_shields.
; ----------------------------------------------------------------------
next_wave: ; Name the address of the next emitted byte; a label emits no bytes.
    inc wave_number ; Advance to the next formation (1, 2, 3, ...)
    jsr update_wave ; Immediately refresh the number on the HUD
    lda #$02 ; Put the literal $02 in A; # selects a value; N/Z reflect it.
    sta direction ; Write A to signed fleet step; a store leaves the CPU flags unchanged.
    lda #$00 ; Put the literal $00 in A; # selects a value; N/Z reflect it.
    sta bullet_active ; Write A to player-shot active flag; a store leaves the CPU flags unchanged.
    sta enemy_fire_clock ; Write A to enemy fire clock; a store leaves the CPU flags unchanged.
    ldx #0 ; Put the literal 0 in X; # selects a value; N/Z reflect it.
next_wave_clear_shots: ; Name the address of the next emitted byte; a label emits no bytes.
    sta enemy_active,x ; Write A to enemy active,x; a store leaves the CPU flags unchanged.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #3 ; Compare X with a value. Compare X with #3; set N/Z/C without changing X; C means >= unsigned.
    bne next_wave_clear_shots ; Branch to next_wave_clear_shots when Z=0 (nonzero/not equal); otherwise continue in sequence.
    jsr init_aliens ; Call init_aliens; push a return address so the callee can return with RTS.
    lda #8 ; New wave starts slowly again. Put the literal 8 in A; # selects a value; N/Z reflect it.
    sta game_ticks ; Write A to fleet-move countdown; a store leaves the CPU flags unchanged.
    jsr redraw_aliens ; Call redraw_aliens; push a return address so the callee can return with RTS.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

alien_row_y: ; Name the address of the next emitted byte; a label emits no bytes.
    !byte 64,94,124 ; Emit these byte values in order; table and bitmap layout depends on them.

; MOVE ALIEN FORMATION

; ----------------------------------------------------------------------
; ROUTINE move_aliens
; WHAT: Living aliens trigger edge checks. direction is signed +2 or -2.
; WHY: Only living aliens should affect edge checks, movement and the invasion condition.
; HOW: On edge, negate direction, drop logical Y by 6, then move horizontally.
; HOW: Changes A X Y flags. May lose a life/reinitialise fleet on invasion.
; ----------------------------------------------------------------------
move_aliens: ; Name the address of the next emitted byte; a label emits no bytes.
; Right limit $F0 leaves room for the full 2-character alien width.
; First check whether any living alien is at the edge of the formation.
; If so, reverse direction and drop the formation; otherwise move sideways.
    lda #$00 ; Put the literal $00 in A; # selects a value; N/Z reflect it.
    sta hit_edge ; Write A to hit edge; a store leaves the CPU flags unchanged.

    ldx #$00 ; Put the literal $00 in X; # selects a value; N/Z reflect it.

edge_check: ; Name the address of the next emitted byte; a label emits no bytes.
    lda alien_alive,x ; Read alien alive,x at the indexed element into A; update N/Z, preserve carry.
    beq edge_next ; Branch to edge_next when Z=1 (zero/equal); otherwise continue in sequence.

    lda direction ; Read signed fleet step into A; update N/Z without changing carry.
    bmi check_left_edge ; Branch if result is negative. Branch to check_left_edge when N=1 (result bit 7 set); otherwise continue in sequence.

; Rightmost glyph must end at column 36 (the T in QUIT).
; 16-bit alien X permits movement past pixel 255.
    lda alien_x_hi,x ; Read alien x hi,x at the indexed element into A; update N/Z, preserve carry.
    cmp #$01 ; Compare A with #$01; set N/Z/C without changing A; C means >= unsigned.
    bcc edge_next ; Jump to edge_next if carry is clear (unsigned less-than after CMP)
    lda alien_x,x ; Read alien x,x at the indexed element into A; update N/Z, preserve carry.
    cmp #$30 ; X=304 maps to character column 35. Compare A with #$30; set N/Z/C without changing A; C means >= unsigned.
    bcs edge_hit ; Jump to edge_hit if carry is set (unsigned >= after CMP)
    jmp edge_next ; Continue at edge_next without saving a subroutine return address.

check_left_edge: ; Name the address of the next emitted byte; a label emits no bytes.
    lda alien_x_hi,x ; Read alien x hi,x at the indexed element into A; update N/Z, preserve carry.
    bne edge_next ; Branch to edge_next when Z=0 (nonzero/not equal); otherwise continue in sequence.
    lda alien_x,x ; Read alien x,x at the indexed element into A; update N/Z, preserve carry.
    cmp #$20 ; Compare A with #$20; set N/Z/C without changing A; C means >= unsigned.
    bcc edge_hit ; Jump to edge_hit if carry is clear (unsigned less-than after CMP)
    jmp edge_next ; Continue at edge_next without saving a subroutine return address.

edge_hit: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$01 ; Put the literal $01 in A; # selects a value; N/Z reflect it.
    sta hit_edge ; Write A to hit edge; a store leaves the CPU flags unchanged.

edge_next: ; Name the address of the next emitted byte; a label emits no bytes.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #$18 ; Compare X with a value. Compare X with #$18; set N/Z/C without changing X; C means >= unsigned.
    bne edge_check ; Branch to edge_check when Z=0 (nonzero/not equal); otherwise continue in sequence.

    lda hit_edge ; Read hit edge into A; update N/Z without changing carry.
    beq move_horizontally ; Branch to move_horizontally when Z=1 (zero/equal); otherwise continue in sequence.

; Reverse direction.
    lda direction ; Read signed fleet step into A; update N/Z without changing carry.
    eor #$ff ; Flip bits selected by mask. Toggle A bits selected by #$ff; update N/Z and preserve carry.
    clc ; Clear carry so ADC starts without adding an extra 1
    adc #$01 ; Add #$01 and carry to A; carry can extend a 16-bit value
    sta direction ; Write A to signed fleet step; a store leaves the CPU flags unchanged.

; Move formation down six pixels.
    ldx #$00 ; Put the literal $00 in X; # selects a value; N/Z reflect it.

drop_aliens: ; Name the address of the next emitted byte; a label emits no bytes.
    lda alien_alive,x ; Read alien alive,x at the indexed element into A; update N/Z, preserve carry.
    beq drop_next ; Branch to drop_next when Z=1 (zero/equal); otherwise continue in sequence.

    clc ; Clear carry so ADC starts without adding an extra 1
    lda alien_y,x ; Read alien y,x at the indexed element into A; update N/Z, preserve carry.
    adc #$06 ; Add #$06 and carry to A; carry can extend a 16-bit value
    sta alien_y,x ; Write A to alien y,x; a store leaves the CPU flags unchanged.

    cmp #$c0 ; Compare A with #$c0; set N/Z/C without changing A; C means >= unsigned.
    bcs aliens_reach_player ; Jump to aliens_reach_player if carry is set (unsigned >= after CMP)

drop_next: ; Name the address of the next emitted byte; a label emits no bytes.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #$18 ; Compare X with a value. Compare X with #$18; set N/Z/C without changing X; C means >= unsigned.
    bne drop_aliens ; Branch to drop_aliens when Z=0 (nonzero/not equal); otherwise continue in sequence.

move_horizontally: ; Name the address of the next emitted byte; a label emits no bytes.
    ldx #$00 ; Put the literal $00 in X; # selects a value; N/Z reflect it.

horizontal_loop: ; Name the address of the next emitted byte; a label emits no bytes.
    lda alien_alive,x ; Read alien alive,x at the indexed element into A; update N/Z, preserve carry.
    beq horizontal_next ; Branch to horizontal_next when Z=1 (zero/equal); otherwise continue in sequence.

    clc ; Clear carry so ADC starts without adding an extra 1
    lda alien_x,x ; Read alien x,x at the indexed element into A; update N/Z, preserve carry.
    adc direction ; Add direction and carry to A; carry can extend a 16-bit value
    sta alien_x,x ; Write A to alien x,x; a store leaves the CPU flags unchanged.
    lda alien_x_hi,x ; Read alien x hi,x at the indexed element into A; update N/Z, preserve carry.
    ldy direction ; Read signed fleet step into Y; update N/Z without changing carry.
    bmi move_x_negative ; Branch if result is negative. Branch to move_x_negative when N=1 (result bit 7 set); otherwise continue in sequence.
    adc #$00 ; Add #$00 and carry to A; carry can extend a 16-bit value
    jmp move_x_high_done ; Continue at move_x_high_done without saving a subroutine return address.
move_x_negative: ; Name the address of the next emitted byte; a label emits no bytes.
    adc #$ff ; Add #$ff and carry to A; carry can extend a 16-bit value
move_x_high_done: ; Name the address of the next emitted byte; a label emits no bytes.
    sta alien_x_hi,x ; Write A to alien x hi,x; a store leaves the CPU flags unchanged.

horizontal_next: ; Name the address of the next emitted byte; a label emits no bytes.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #$18 ; Compare X with a value. Compare X with #$18; set N/Z/C without changing X; C means >= unsigned.
    bne horizontal_loop ; Branch to horizontal_loop when Z=0 (nonzero/not equal); otherwise continue in sequence.

    rts ; Pull the saved call address and add one; resume after the calling JSR.

aliens_reach_player: ; Name the address of the next emitted byte; a label emits no bytes.
; Aliens reaching the bottom cost one life, not instant game over.
    lda invulnerable ; Read invulnerable into A; update N/Z without changing carry.
    bne aliens_reach_done ; Branch to aliens_reach_done when Z=0 (nonzero/not equal); otherwise continue in sequence.
    jsr lose_life ; Call lose_life; push a return address so the callee can return with RTS.
; Reset formation away from ship if any lives remain.
    lda game_over ; Read game-over flag into A; update N/Z without changing carry.
    bne aliens_reach_done ; Branch to aliens_reach_done when Z=0 (nonzero/not equal); otherwise continue in sequence.
    jsr init_aliens ; Call init_aliens; push a return address so the callee can return with RTS.
    jsr redraw_aliens ; Call redraw_aliens; push a return address so the callee can return with RTS.
aliens_reach_done: ; Name the address of the next emitted byte; a label emits no bytes.
    rts ; Pull the saved call address and add one; resume after the calling JSR.


hit_alien_index: !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
collision_left: !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
collision_top:  !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
collision_row_bottom: !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.

; HUD AND SCORE

; ----------------------------------------------------------------------
; ROUTINE clear_screen
; WHAT: Writes exactly 1000 spaces and white colour entries.
; WHY: Old display contents must be removed without accidentally overwriting the sprite pointer table.
; HOW: Three full pages plus 232 bytes. Does not overwrite live sprite pointers.
; HOW: Changes A X flags. Requires normal I/O mapping.
; ----------------------------------------------------------------------
clear_screen: ; Name the address of the next emitted byte; a label emits no bytes.
; Clear EXACTLY 1000 screen cells, not 1024 or more.
; The previous version wrote from $07E8 into $08E7,
; overwriting the BASIC launcher and live machine code!
    ldx #$00 ; Put the literal $00 in X; # selects a value; N/Z reflect it.
clear_full_pages: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$20 ; Put the literal $20 in A; # selects a value; N/Z reflect it.
    sta SCREEN,x ; Write A to SCREEN,x; a store leaves the CPU flags unchanged.
    sta SCREEN+$100,x ; Write A to SCREEN+$100,x; a store leaves the CPU flags unchanged.
    sta SCREEN+$200,x ; Write A to SCREEN+$200,x; a store leaves the CPU flags unchanged.
    lda #$01 ; Put the literal $01 in A; # selects a value; N/Z reflect it.
    sta COLOR,x ; Write A to COLOR,x; a store leaves the CPU flags unchanged.
    sta COLOR+$100,x ; Write A to COLOR+$100,x; a store leaves the CPU flags unchanged.
    sta COLOR+$200,x ; Write A to COLOR+$200,x; a store leaves the CPU flags unchanged.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    bne clear_full_pages ; Branch to clear_full_pages when Z=0 (nonzero/not equal); otherwise continue in sequence.

; 1000 - 768 = 232 remaining cells.
    ldx #$00 ; Put the literal $00 in X; # selects a value; N/Z reflect it.
clear_last_cells: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$20 ; Put the literal $20 in A; # selects a value; N/Z reflect it.
    sta SCREEN+$300,x ; Write A to SCREEN+$300,x; a store leaves the CPU flags unchanged.
    lda #$01 ; Put the literal $01 in A; # selects a value; N/Z reflect it.
    sta COLOR+$300,x ; Write A to COLOR+$300,x; a store leaves the CPU flags unchanged.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #232 ; Compare X with a value. Compare X with #232; set N/Z/C without changing X; C means >= unsigned.
    bne clear_last_cells ; Branch to clear_last_cells when Z=0 (nonzero/not equal); otherwise continue in sequence.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; ----------------------------------------------------------------------
; ROUTINE draw_hud
; WHAT: Copies title_text to row 0 and score_text to row 1.
; WHY: Fixed labels and controls belong in a common template, separate from frequently changing numbers.
; HOW: This is a template; update_score writes four digits over part of that template.
; HOW: Changes A X flags. Known lives/wave overlap is documented in Chapter 14.
; ----------------------------------------------------------------------
draw_hud: ; Name the address of the next emitted byte; a label emits no bytes.
; Copy the title and the fixed HUD label to screen RAM.
; PETSCII/screen codes are stored as bytes in the text tables below.
    ldx #$00 ; Put the literal $00 in X; # selects a value; N/Z reflect it.

title_loop: ; Name the address of the next emitted byte; a label emits no bytes.
    lda title_text,x ; Read title text,x at the indexed element into A; update N/Z, preserve carry.
    beq title_done ; Branch to title_done when Z=1 (zero/equal); otherwise continue in sequence.

    sta SCREEN,x ; Write A to SCREEN,x; a store leaves the CPU flags unchanged.
    lda #$07 ; Put the literal $07 in A; # selects a value; N/Z reflect it.
    sta COLOR,x ; Write A to COLOR,x; a store leaves the CPU flags unchanged.

    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    bne title_loop ; Branch to title_loop when Z=0 (nonzero/not equal); otherwise continue in sequence.

title_done: ; Name the address of the next emitted byte; a label emits no bytes.
    ldx #$00 ; Put the literal $00 in X; # selects a value; N/Z reflect it.

hud_loop: ; Name the address of the next emitted byte; a label emits no bytes.
    lda score_text,x ; Read score text,x at the indexed element into A; update N/Z, preserve carry.
    beq hud_done ; Branch to hud_done when Z=1 (zero/equal); otherwise continue in sequence.

    sta SCREEN+40,x ; Write A to SCREEN+40,x; a store leaves the CPU flags unchanged.
    lda #$01 ; Put the literal $01 in A; # selects a value; N/Z reflect it.
    sta COLOR+40,x ; Write A to COLOR+40,x; a store leaves the CPU flags unchanged.

    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #$28 ; Compare X with a value. Compare X with #$28; set N/Z/C without changing X; C means >= unsigned.
    bne hud_loop ; Branch to hud_loop when Z=0 (nonzero/not equal); otherwise continue in sequence.

hud_done: ; Name the address of the next emitted byte; a label emits no bytes.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; WAVE COUNTER (TOP RIGHT OF SCREEN)
; The VIC-II screen uses character codes rather than PETSCII.
; Letter W is $17, A is $01, V is $16, E is $05.
; Numeric screen codes $30..$39 represent digits 0..9.
; We reserve screen row 0, columns 30..38 for "WAVE: 001".
; The wave number is one byte, so it counts from 1 to 255.

; ----------------------------------------------------------------------
; ROUTINE update_wave
; WHAT: Converts byte wave_number to three screen digits at row 0 columns 36..38.
; WHY: A binary counter must be converted into decimal screen digits before a reader can see its value.
; HOW: Writes WAVE label at columns 30..34, overlapping current lives field.
; HOW: Changes A X flags and wave_work. Uses binary repeated subtraction.
; ----------------------------------------------------------------------
update_wave: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$17 ; W. Put the literal $17 in A; # selects a value; N/Z reflect it.
    sta SCREEN+30 ; Write A to SCREEN+30; a store leaves the CPU flags unchanged.
    lda #$01 ; A. Put the literal $01 in A; # selects a value; N/Z reflect it.
    sta SCREEN+31 ; Write A to SCREEN+31; a store leaves the CPU flags unchanged.
    lda #$16 ; V. Put the literal $16 in A; # selects a value; N/Z reflect it.
    sta SCREEN+32 ; Write A to SCREEN+32; a store leaves the CPU flags unchanged.
    lda #$05 ; E. Put the literal $05 in A; # selects a value; N/Z reflect it.
    sta SCREEN+33 ; Write A to SCREEN+33; a store leaves the CPU flags unchanged.
    lda #$3a ; :. Put the literal $3a in A; # selects a value; N/Z reflect it.
    sta SCREEN+34 ; Write A to SCREEN+34; a store leaves the CPU flags unchanged.
    lda #$20 ; space. Put the literal $20 in A; # selects a value; N/Z reflect it.
    sta SCREEN+35 ; Write A to SCREEN+35; a store leaves the CPU flags unchanged.

    lda wave_number ; Copy the current wave into a work byte.
    sta wave_work ; Write A to wave work; a store leaves the CPU flags unchanged.
    ldx #$00 ; X counts hundreds.. Put the literal $00 in X; # selects a value; N/Z reflect it.
wave_hundreds_loop: ; Name the address of the next emitted byte; a label emits no bytes.
    lda wave_work ; Read wave work into A; update N/Z without changing carry.
    cmp #100 ; Carry set when value is at least 100.
    bcc wave_hundreds_done ; Jump to wave_hundreds_done if carry is clear (unsigned less-than after CMP)
    sec ; Set carry so SBC subtracts without an extra borrow
    sbc #100 ; Subtract #100 and borrow from A. Subtract #100 and the incoming borrow from A; C=1 means no borrow.
    sta wave_work ; Write A to wave work; a store leaves the CPU flags unchanged.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    jmp wave_hundreds_loop ; Continue at wave_hundreds_loop without saving a subroutine return address.
wave_hundreds_done: ; Name the address of the next emitted byte; a label emits no bytes.
    txa ; Turn the hundreds digit into screen code.
    clc ; Clear carry so ADC starts without adding an extra 1
    adc #$30 ; Add #$30 and carry to A; carry can extend a 16-bit value
    sta SCREEN+36 ; Write A to SCREEN+36; a store leaves the CPU flags unchanged.

    ldx #$00 ; X now counts tens.. Put the literal $00 in X; # selects a value; N/Z reflect it.
wave_tens_loop: ; Name the address of the next emitted byte; a label emits no bytes.
    lda wave_work ; Read wave work into A; update N/Z without changing carry.
    cmp #10 ; Compare A with #10; set N/Z/C without changing A; C means >= unsigned.
    bcc wave_tens_done ; Jump to wave_tens_done if carry is clear (unsigned less-than after CMP)
    sec ; Set carry so SBC subtracts without an extra borrow
    sbc #10 ; Subtract #10 and borrow from A. Subtract #10 and the incoming borrow from A; C=1 means no borrow.
    sta wave_work ; Write A to wave work; a store leaves the CPU flags unchanged.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    jmp wave_tens_loop ; Continue at wave_tens_loop without saving a subroutine return address.
wave_tens_done: ; Name the address of the next emitted byte; a label emits no bytes.
    txa ; Copy X to A. Copy X to A; N/Z reflect the copied byte.
    clc ; Clear carry so ADC starts without adding an extra 1
    adc #$30 ; Add #$30 and carry to A; carry can extend a 16-bit value
    sta SCREEN+37 ; Write A to SCREEN+37; a store leaves the CPU flags unchanged.
    lda wave_work ; What remains is the units digit (0..9).
    clc ; Clear carry so ADC starts without adding an extra 1
    adc #$30 ; Add #$30 and carry to A; carry can extend a 16-bit value
    sta SCREEN+38 ; Write A to SCREEN+38; a store leaves the CPU flags unchanged.

    ldx #30 ; Make all nine HUD cells white.. Put the literal 30 in X; # selects a value; N/Z reflect it.
wave_colour_loop: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$01 ; Put the literal $01 in A; # selects a value; N/Z reflect it.
    sta COLOR,x ; Write A to COLOR,x; a store leaves the CPU flags unchanged.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #39 ; Compare X with a value. Compare X with #39; set N/Z/C without changing X; C means >= unsigned.
    bne wave_colour_loop ; Branch to wave_colour_loop when Z=0 (nonzero/not equal); otherwise continue in sequence.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; ----------------------------------------------------------------------
; ROUTINE update_score
; WHAT: Converts score_hi:score into four digits at row 1 columns 7..10.
; WHY: The two-byte binary score cannot be displayed by storing its raw bytes into screen RAM.
; HOW: Caller caps value at 1000; this is binary arithmetic, not BCD.
; HOW: Changes A X flags and score work bytes.
; ----------------------------------------------------------------------
update_score: ; Name the address of the next emitted byte; a label emits no bytes.
; Four decimal digits 0000..1000 in HUD columns 7..10.
; Work on a 16-bit copy, subtracting place values.
    lda score ; Read binary score low byte into A; update N/Z without changing carry.
    sta score_work_lo ; Write A to score work lo; a store leaves the CPU flags unchanged.
    lda score_hi ; Read binary score high byte into A; update N/Z without changing carry.
    sta score_work_hi ; Write A to score work hi; a store leaves the CPU flags unchanged.
    ldx #$00 ; Put the literal $00 in X; # selects a value; N/Z reflect it.
score_thousands: ; Name the address of the next emitted byte; a label emits no bytes.
    lda score_work_hi ; Read score work hi into A; update N/Z without changing carry.
    cmp #$03 ; Compare A with #$03; set N/Z/C without changing A; C means >= unsigned.
    bcc score_thousands_done ; Jump to score_thousands_done if carry is clear (unsigned less-than after CMP)
    bne score_thousands_sub ; Branch to score_thousands_sub when Z=0 (nonzero/not equal); otherwise continue in sequence.
    lda score_work_lo ; Read score work lo into A; update N/Z without changing carry.
    cmp #$e8 ; Compare A with #$e8; set N/Z/C without changing A; C means >= unsigned.
    bcc score_thousands_done ; Jump to score_thousands_done if carry is clear (unsigned less-than after CMP)
score_thousands_sub: ; Name the address of the next emitted byte; a label emits no bytes.
    sec ; Set carry so SBC subtracts without an extra borrow
    lda score_work_lo ; Read score work lo into A; update N/Z without changing carry.
    sbc #$e8 ; Subtract #$e8 and borrow from A. Subtract #$e8 and the incoming borrow from A; C=1 means no borrow.
    sta score_work_lo ; Write A to score work lo; a store leaves the CPU flags unchanged.
    lda score_work_hi ; Read score work hi into A; update N/Z without changing carry.
    sbc #$03 ; Subtract #$03 and borrow from A. Subtract #$03 and the incoming borrow from A; C=1 means no borrow.
    sta score_work_hi ; Write A to score work hi; a store leaves the CPU flags unchanged.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    jmp score_thousands ; Continue at score_thousands without saving a subroutine return address.
score_thousands_done: ; Name the address of the next emitted byte; a label emits no bytes.
    txa ; Copy X to A. Copy X to A; N/Z reflect the copied byte.
    clc ; Clear carry so ADC starts without adding an extra 1
    adc #$30 ; Add #$30 and carry to A; carry can extend a 16-bit value
    sta SCREEN+47 ; Write A to SCREEN+47; a store leaves the CPU flags unchanged.
    ldx #$00 ; Put the literal $00 in X; # selects a value; N/Z reflect it.
score_hundreds: ; Name the address of the next emitted byte; a label emits no bytes.
    lda score_work_hi ; Read score work hi into A; update N/Z without changing carry.
    bne score_hundreds_sub ; Branch to score_hundreds_sub when Z=0 (nonzero/not equal); otherwise continue in sequence.
    lda score_work_lo ; Read score work lo into A; update N/Z without changing carry.
    cmp #100 ; Compare A with #100; set N/Z/C without changing A; C means >= unsigned.
    bcc score_hundreds_done ; Jump to score_hundreds_done if carry is clear (unsigned less-than after CMP)
score_hundreds_sub: ; Name the address of the next emitted byte; a label emits no bytes.
    sec ; Set carry so SBC subtracts without an extra borrow
    lda score_work_lo ; Read score work lo into A; update N/Z without changing carry.
    sbc #100 ; Subtract #100 and borrow from A. Subtract #100 and the incoming borrow from A; C=1 means no borrow.
    sta score_work_lo ; Write A to score work lo; a store leaves the CPU flags unchanged.
    lda score_work_hi ; Read score work hi into A; update N/Z without changing carry.
    sbc #0 ; Subtract #0 and borrow from A. Subtract #0 and the incoming borrow from A; C=1 means no borrow.
    sta score_work_hi ; Write A to score work hi; a store leaves the CPU flags unchanged.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    jmp score_hundreds ; Continue at score_hundreds without saving a subroutine return address.
score_hundreds_done: ; Name the address of the next emitted byte; a label emits no bytes.
    txa ; Copy X to A. Copy X to A; N/Z reflect the copied byte.
    clc ; Clear carry so ADC starts without adding an extra 1
    adc #$30 ; Add #$30 and carry to A; carry can extend a 16-bit value
    sta SCREEN+48 ; Write A to SCREEN+48; a store leaves the CPU flags unchanged.
    ldx #$00 ; Put the literal $00 in X; # selects a value; N/Z reflect it.
score_tens: ; Name the address of the next emitted byte; a label emits no bytes.
    lda score_work_lo ; Read score work lo into A; update N/Z without changing carry.
    cmp #10 ; Compare A with #10; set N/Z/C without changing A; C means >= unsigned.
    bcc score_tens_done ; Jump to score_tens_done if carry is clear (unsigned less-than after CMP)
    sec ; Set carry so SBC subtracts without an extra borrow
    sbc #10 ; Subtract #10 and borrow from A. Subtract #10 and the incoming borrow from A; C=1 means no borrow.
    sta score_work_lo ; Write A to score work lo; a store leaves the CPU flags unchanged.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    jmp score_tens ; Continue at score_tens without saving a subroutine return address.
score_tens_done: ; Name the address of the next emitted byte; a label emits no bytes.
    txa ; Copy X to A. Copy X to A; N/Z reflect the copied byte.
    clc ; Clear carry so ADC starts without adding an extra 1
    adc #$30 ; Add #$30 and carry to A; carry can extend a 16-bit value
    sta SCREEN+49 ; Write A to SCREEN+49; a store leaves the CPU flags unchanged.
    lda score_work_lo ; Read score work lo into A; update N/Z without changing carry.
    clc ; Clear carry so ADC starts without adding an extra 1
    adc #$30 ; Add #$30 and carry to A; carry can extend a 16-bit value
    sta SCREEN+50 ; Write A to SCREEN+50; a store leaves the CPU flags unchanged.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; ONE RASTER IRQ PER FRAME - player sprite 0 and bullet sprite 7
; No alien sprite multiplexing, avoiding flicker and missing rows.
; ----------------------------------------------------------------------
; ROUTINE raster_irq
; WHAT: Entry via standard KERNAL RAM IRQ vector after standard register saves.
; WHY: Publishing sprite registers at a common raster event gives the hardware a regular view of game state.
; HOW: VIC path acknowledges $D019, publishes sprite state, increments frame_count.
; HOW: Jumps $EA31 for normal KERNAL service. Do not use as a bare hardware-vector ISR.
; ----------------------------------------------------------------------
raster_irq: ; Name the address of the next emitted byte; a label emits no bytes.
    lda $d019 ; Read VIC interrupt status/acknowledge into A; update N/Z without changing carry.
    and #$01 ; Keep only bits selected by mask. Keep only bits shared with #$01; A and N/Z change; carry is preserved.
    bne irq_raster_pending ; Branch to irq_raster_pending when Z=0 (nonzero/not equal); otherwise continue in sequence.
    jmp irq_exit ; Continue at irq_exit without saving a subroutine return address.
irq_raster_pending: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$01 ; Put the literal $01 in A; # selects a value; N/Z reflect it.
    sta $d019 ; Write A to VIC interrupt status/acknowledge; a store leaves the CPU flags unchanged.

    lda explosion_timer ; Read explosion timer into A; update N/Z without changing carry.
    beq irq_normal_ship ; Branch to irq_normal_ship when Z=1 (zero/equal); otherwise continue in sequence.
    lda #$84 ; Explosion sprite graphic at $2100. Put the literal $84 in A; # selects a value; N/Z reflect it.
    bne irq_ship_pointer ; Branch to irq_ship_pointer when Z=0 (nonzero/not equal); otherwise continue in sequence.
irq_normal_ship: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$81 ; Normal ship graphic at $2040. Put the literal $81 in A; # selects a value; N/Z reflect it.
irq_ship_pointer: ; Name the address of the next emitted byte; a label emits no bytes.
    sta $07f8 ; Write A to sprite-0 bitmap pointer; a store leaves the CPU flags unchanged.
    lda player_x ; Read player X low byte into A; update N/Z without changing carry.
    sta $d000 ; Write A to $d000; a store leaves the CPU flags unchanged.
    lda #$dc ; Put the literal $dc in A; # selects a value; N/Z reflect it.
    sta $d001 ; Write A to $d001; a store leaves the CPU flags unchanged.
    lda explosion_timer ; Read explosion timer into A; update N/Z without changing carry.
    beq irq_ship_white ; Branch to irq_ship_white when Z=1 (zero/equal); otherwise continue in sequence.
    and #$04 ; Keep only bits selected by mask. Keep only bits shared with #$04; A and N/Z change; carry is preserved.
    beq irq_ship_yellow ; Branch to irq_ship_yellow when Z=1 (zero/equal); otherwise continue in sequence.
    lda #$02 ; Red explosion flash. Put the literal $02 in A; # selects a value; N/Z reflect it.
    bne irq_ship_colour ; Branch to irq_ship_colour when Z=0 (nonzero/not equal); otherwise continue in sequence.
irq_ship_yellow: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$07 ; Yellow explosion flash. Put the literal $07 in A; # selects a value; N/Z reflect it.
    bne irq_ship_colour ; Branch to irq_ship_colour when Z=0 (nonzero/not equal); otherwise continue in sequence.
irq_ship_white: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$01 ; Put the literal $01 in A; # selects a value; N/Z reflect it.
irq_ship_colour: ; Name the address of the next emitted byte; a label emits no bytes.
    sta $d027 ; Write A to $d027; a store leaves the CPU flags unchanged.

; Sprites 1, 2 and 3 are descending enemy shots.
; $83 points to their shared small bolt graphic at $20C0.
    ldx #0 ; Put the literal 0 in X; # selects a value; N/Z reflect it.
irq_enemy_loop: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$83 ; Put the literal $83 in A; # selects a value; N/Z reflect it.
    sta $07f9,x ; Write A to $07f9,x; a store leaves the CPU flags unchanged.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #3 ; Compare X with a value. Compare X with #3; set N/Z/C without changing X; C means >= unsigned.
    bne irq_enemy_loop ; Branch to irq_enemy_loop when Z=0 (nonzero/not equal); otherwise continue in sequence.

    lda enemy_x ; Read enemy x into A; update N/Z without changing carry.
    sta $d002 ; Write A to $d002; a store leaves the CPU flags unchanged.
    lda enemy_y ; Read enemy y into A; update N/Z without changing carry.
    sta $d003 ; Write A to $d003; a store leaves the CPU flags unchanged.
    lda enemy_x+1 ; Read enemy x+1 into A; update N/Z without changing carry.
    sta $d004 ; Write A to $d004; a store leaves the CPU flags unchanged.
    lda enemy_y+1 ; Read enemy y+1 into A; update N/Z without changing carry.
    sta $d005 ; Write A to $d005; a store leaves the CPU flags unchanged.
    lda enemy_x+2 ; Read enemy x+2 into A; update N/Z without changing carry.
    sta $d006 ; Write A to $d006; a store leaves the CPU flags unchanged.
    lda enemy_y+2 ; Read enemy y+2 into A; update N/Z without changing carry.
    sta $d007 ; Write A to $d007; a store leaves the CPU flags unchanged.
    lda #$02 ; Put the literal $02 in A; # selects a value; N/Z reflect it.
    sta $d028 ; Write A to $d028; a store leaves the CPU flags unchanged.
    sta $d029 ; Write A to $d029; a store leaves the CPU flags unchanged.
    sta $d02a ; Write A to $d02a; a store leaves the CPU flags unchanged.

    lda #$82 ; Put the literal $82 in A; # selects a value; N/Z reflect it.
    sta $07ff ; Write A to sprite-7 bitmap pointer; a store leaves the CPU flags unchanged.
    lda bullet_x ; Read player shot X low byte into A; update N/Z without changing carry.
    sta $d00e ; Write A to $d00e; a store leaves the CPU flags unchanged.
    lda #$01 ; Put the literal $01 in A; # selects a value; N/Z reflect it.
    sta $d02e ; Write A to $d02e; a store leaves the CPU flags unchanged.
    lda bullet_active ; Read player-shot active flag into A; update N/Z without changing carry.
    beq irq_no_bullet ; Branch to irq_no_bullet when Z=1 (zero/equal); otherwise continue in sequence.
    lda bullet_y ; Read player shot Y into A; update N/Z without changing carry.
    sta $d00f ; Write A to $d00f; a store leaves the CPU flags unchanged.
    lda #$81 ; Put the literal $81 in A; # selects a value; N/Z reflect it.
    bne irq_enable ; Branch to irq_enable when Z=0 (nonzero/not equal); otherwise continue in sequence.
irq_no_bullet: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$ff ; Put the literal $ff in A; # selects a value; N/Z reflect it.
    sta $d00f ; Write A to $d00f; a store leaves the CPU flags unchanged.
    lda #$01 ; Put the literal $01 in A; # selects a value; N/Z reflect it.
irq_enable: ; Name the address of the next emitted byte; a label emits no bytes.
    sta sprite_enable_work ; Write A to sprite enable work; a store leaves the CPU flags unchanged.
    ldx #0 ; Put the literal 0 in X; # selects a value; N/Z reflect it.
irq_enemy_enable_loop: ; Name the address of the next emitted byte; a label emits no bytes.
    lda enemy_active,x ; Read enemy active,x at the indexed element into A; update N/Z, preserve carry.
    beq irq_enemy_enable_next ; Branch to irq_enemy_enable_next when Z=1 (zero/equal); otherwise continue in sequence.
    lda sprite_enable_work ; Read sprite enable work into A; update N/Z without changing carry.
    ora enemy_bits,x ; Set bits selected by mask. Set A bits selected by enemy_bits,x; preserve other bits and carry; update N/Z.
    sta sprite_enable_work ; Write A to sprite enable work; a store leaves the CPU flags unchanged.
irq_enemy_enable_next: ; Name the address of the next emitted byte; a label emits no bytes.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #3 ; Compare X with a value. Compare X with #3; set N/Z/C without changing X; C means >= unsigned.
    bne irq_enemy_enable_loop ; Branch to irq_enemy_enable_loop when Z=0 (nonzero/not equal); otherwise continue in sequence.
    lda sprite_enable_work ; Read sprite enable work into A; update N/Z without changing carry.
    sta $d015 ; Write A to sprite enable mask; a store leaves the CPU flags unchanged.
    lda #$00 ; Put the literal $00 in A; # selects a value; N/Z reflect it.
    ldx player_x_hi ; Read player X high byte into X; update N/Z without changing carry.
    beq irq_check_bullet_msb ; Branch to irq_check_bullet_msb when Z=1 (zero/equal); otherwise continue in sequence.
    ora #$01 ; Set bits selected by mask. Set A bits selected by #$01; preserve other bits and carry; update N/Z.
irq_check_bullet_msb: ; Name the address of the next emitted byte; a label emits no bytes.
    ldx bullet_x_hi ; Read player shot X high byte into X; update N/Z without changing carry.
    beq irq_write_x_msb ; Branch to irq_write_x_msb when Z=1 (zero/equal); otherwise continue in sequence.
    ora #$80 ; Set bits selected by mask. Set A bits selected by #$80; preserve other bits and carry; update N/Z.
irq_write_x_msb: ; Name the address of the next emitted byte; a label emits no bytes.
    sta sprite_msb_work ; Write A to sprite msb work; a store leaves the CPU flags unchanged.
    ldx #0 ; Put the literal 0 in X; # selects a value; N/Z reflect it.
irq_enemy_msb_loop: ; Name the address of the next emitted byte; a label emits no bytes.
    lda enemy_active,x ; Read enemy active,x at the indexed element into A; update N/Z, preserve carry.
    beq irq_enemy_msb_next ; Branch to irq_enemy_msb_next when Z=1 (zero/equal); otherwise continue in sequence.
    lda enemy_x_hi,x ; Read enemy x hi,x at the indexed element into A; update N/Z, preserve carry.
    beq irq_enemy_msb_next ; Branch to irq_enemy_msb_next when Z=1 (zero/equal); otherwise continue in sequence.
    lda sprite_msb_work ; Read sprite msb work into A; update N/Z without changing carry.
    ora enemy_bits,x ; Set bits selected by mask. Set A bits selected by enemy_bits,x; preserve other bits and carry; update N/Z.
    sta sprite_msb_work ; Write A to sprite msb work; a store leaves the CPU flags unchanged.
irq_enemy_msb_next: ; Name the address of the next emitted byte; a label emits no bytes.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #3 ; Compare X with a value. Compare X with #3; set N/Z/C without changing X; C means >= unsigned.
    bne irq_enemy_msb_loop ; Branch to irq_enemy_msb_loop when Z=0 (nonzero/not equal); otherwise continue in sequence.
    lda sprite_msb_work ; Read sprite msb work into A; update N/Z without changing carry.
    sta $d010 ; Write A to sprite ninth-X-bit mask; a store leaves the CPU flags unchanged.
    inc frame_count ; Increase IRQ frame counter by one modulo 256; set N/Z, preserve carry.
irq_exit: ; Name the address of the next emitted byte; a label emits no bytes.
    jmp $ea31 ; Continue at $ea31 without saving a subroutine return address.

; COPY C64 CHARACTER ROM INTO RAM AT $3000 AND DEFINE ALIEN GLYPHS.
; VIC bank 0, screen at $0400, charset at $3000 ($D018=$1C).
; Character codes $60 and $61 form one 16x8 alien.
; ----------------------------------------------------------------------
; ROUTINE install_alien_charset
; WHAT: Caller has IRQs disabled. Temporarily maps character ROM with $01=$33.
; WHY: ROM patterns cannot be edited, so the game first copies them to writable character RAM.
; HOW: Copies 2048 bytes to $3000, installs custom glyphs, selects $D018=$1C.
; HOW: Restores $01. Changes A X Y flags and $FB..$FE. Assumes VIC bank 0.
; ----------------------------------------------------------------------
install_alien_charset: ; Name the address of the next emitted byte; a label emits no bytes.
    lda $01 ; Read CPU memory-banking port into A; update N/Z without changing carry.
    sta saved_memory_config ; Write A to saved memory config; a store leaves the CPU flags unchanged.
    lda #$33 ; make character ROM visible to CPU at $D000
    sta $01 ; Write A to CPU memory-banking port; a store leaves the CPU flags unchanged.
    lda #$00 ; Put the literal $00 in A; # selects a value; N/Z reflect it.
    sta $fb ; Write A to first pointer low byte; a store leaves the CPU flags unchanged.
    sta $fd ; Write A to second pointer low byte; a store leaves the CPU flags unchanged.
    lda #$d0 ; Put the literal $d0 in A; # selects a value; N/Z reflect it.
    sta $fc ; Write A to first pointer high byte; a store leaves the CPU flags unchanged.
    lda #$30 ; Put the literal $30 in A; # selects a value; N/Z reflect it.
    sta $fe ; Write A to second pointer high byte; a store leaves the CPU flags unchanged.
    ldx #$08 ; copy 8 x 256 = 2048 bytes. Put the literal $08 in X; # selects a value; N/Z reflect it.
charset_page: ; Name the address of the next emitted byte; a label emits no bytes.
    ldy #$00 ; Put the literal $00 in Y; # selects a value; N/Z reflect it.
charset_byte: ; Name the address of the next emitted byte; a label emits no bytes.
    lda ($fb),y ; Follow the zero-page pointer, add the index, and read into A; set N/Z.
    sta ($fd),y ; Write A through the pointer plus index; CPU flags stay unchanged.
    iny ; Increase Y by one modulo 256; set N/Z, preserve carry.
    bne charset_byte ; Branch to charset_byte when Z=0 (nonzero/not equal); otherwise continue in sequence.
    inc $fc ; Increase first pointer high byte by one modulo 256; set N/Z, preserve carry.
    inc $fe ; Increase second pointer high byte by one modulo 256; set N/Z, preserve carry.
    dex ; Decrease X by one modulo 256; set N/Z, preserve carry.
    bne charset_page ; Branch to charset_page when Z=0 (nonzero/not equal); otherwise continue in sequence.
    lda saved_memory_config ; Read saved memory config into A; update N/Z without changing carry.
    sta $01 ; Write A to CPU memory-banking port; a store leaves the CPU flags unchanged.
; Each alien is 16 pixels wide: two neighbouring 8x8 characters.
; The top, middle and bottom rows use separate character pairs.
; $60/$61 at $3300/$3308: top (squid)
; $62/$63 at $3310/$3318: middle (crab)
; $64/$65 at $3320/$3328: bottom (octopus)
; X counts the eight scan lines of every character.
    ldx #$00 ; Put the literal $00 in X; # selects a value; N/Z reflect it.
alien_glyph_copy: ; Name the address of the next emitted byte; a label emits no bytes.
    lda alien_glyph_left,x ; Read alien glyph left,x at the indexed element into A; update N/Z, preserve carry.
    sta $3300,x ; Write A to $3300,x; a store leaves the CPU flags unchanged.
    lda alien_glyph_right,x ; Read alien glyph right,x at the indexed element into A; update N/Z, preserve carry.
    sta $3308,x ; Write A to $3308,x; a store leaves the CPU flags unchanged.
    lda alien_crab_left,x ; Read alien crab left,x at the indexed element into A; update N/Z, preserve carry.
    sta $3310,x ; Write A to $3310,x; a store leaves the CPU flags unchanged.
    lda alien_crab_right,x ; Read alien crab right,x at the indexed element into A; update N/Z, preserve carry.
    sta $3318,x ; Write A to $3318,x; a store leaves the CPU flags unchanged.
    lda alien_octopus_left,x ; Read alien octopus left,x at the indexed element into A; update N/Z, preserve carry.
    sta $3320,x ; Write A to $3320,x; a store leaves the CPU flags unchanged.
    lda alien_octopus_right,x ; Read alien octopus right,x at the indexed element into A; update N/Z, preserve carry.
    sta $3328,x ; Write A to $3328,x; a store leaves the CPU flags unchanged.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #$08 ; Compare X with #$08; set N/Z/C without changing X; C means >= unsigned.
    bne alien_glyph_copy ; Branch to alien_glyph_copy when Z=0 (nonzero/not equal); otherwise continue in sequence.
; Shield glyphs $68/$69/$6A at $3340/$3348/$3350.
    ldx #0 ; Put the literal 0 in X; # selects a value; N/Z reflect it.
shield_glyph_install: ; Name the address of the next emitted byte; a label emits no bytes.
    lda shield_glyph_full,x ; Read shield glyph full,x at the indexed element into A; update N/Z, preserve carry.
    sta $3340,x ; Write A to $3340,x; a store leaves the CPU flags unchanged.
    lda shield_glyph_damaged,x ; Read shield glyph damaged,x at the indexed element into A; update N/Z, preserve carry.
    sta $3348,x ; Write A to $3348,x; a store leaves the CPU flags unchanged.
    lda shield_glyph_crumbling,x ; Read shield glyph crumbling,x at the indexed element into A; update N/Z, preserve carry.
    sta $3350,x ; Write A to $3350,x; a store leaves the CPU flags unchanged.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #8 ; Compare X with a value. Compare X with #8; set N/Z/C without changing X; C means >= unsigned.
    bne shield_glyph_install ; Branch to shield_glyph_install when Z=0 (nonzero/not equal); otherwise continue in sequence.
    jsr install_shifted_glyphs ; Call install_shifted_glyphs; push a return address so the callee can return with RTS.
    lda #$1c ; Put the literal $1c in A; # selects a value; N/Z reflect it.
    sta $d018 ; Write A to screen and character selection; a store leaves the CPU flags unchanged.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

shield_glyph_full: ; Name the address of the next emitted byte; a label emits no bytes.
    !byte %11111111,%11111111,%11111111,%11111111 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %11111111,%11111111,%11111111,%11111111 ; Emit these byte values in order; table and bitmap layout depends on them.
shield_glyph_damaged: ; Name the address of the next emitted byte; a label emits no bytes.
    !byte %11111111,%11101111,%11011111,%11111011 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %11110111,%10111111,%11111101,%11111111 ; Emit these byte values in order; table and bitmap layout depends on them.
shield_glyph_crumbling: ; Name the address of the next emitted byte; a label emits no bytes.
    !byte %11001011,%01110100,%10101101,%01010010 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %11001001,%00110110,%10100101,%01011000 ; Emit these byte values in order; table and bitmap layout depends on them.
saved_memory_config: !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
alien_glyph_left: ; Name the address of the next emitted byte; a label emits no bytes.
    !byte %00000000,%00000111,%00011111,%00111111 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %01110111,%01111111,%00101010,%01000100 ; Emit these byte values in order; table and bitmap layout depends on them.
alien_glyph_right: ; Name the address of the next emitted byte; a label emits no bytes.
    !byte %00000000,%11100000,%11111000,%11111100 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %11101110,%11111110,%01010100,%00100010 ; Emit these byte values in order; table and bitmap layout depends on them.

; MIDDLE ROW: crab-like alien, 16x8 pixels (left and right halves).
; A 1 is a lit pixel, a 0 is background. Read each binary row left-to-right.
alien_crab_left: ; Name the address of the next emitted byte; a label emits no bytes.
    !byte %00000000,%01000010,%00100100,%01111111 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %11011011,%11111111,%10100101,%00100100 ; Emit these byte values in order; table and bitmap layout depends on them.
alien_crab_right: ; Name the address of the next emitted byte; a label emits no bytes.
    !byte %00000000,%01000010,%00100100,%11111110 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %11011011,%11111111,%10100101,%00100100 ; Emit these byte values in order; table and bitmap layout depends on them.

; BOTTOM ROW: wide octopus with two hanging tentacles.
alien_octopus_left: ; Name the address of the next emitted byte; a label emits no bytes.
    !byte %00000000,%00011111,%00111111,%01101111 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %11111111,%11111111,%00110110,%01100011 ; Emit these byte values in order; table and bitmap layout depends on them.
alien_octopus_right: ; Name the address of the next emitted byte; a label emits no bytes.
    !byte %00000000,%11111000,%11111100,%11110110 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %11111111,%11111111,%01101100,%11000110 ; Emit these byte values in order; table and bitmap layout depends on them.


; DRAW 24 ALIENS AS THREE-CELL PIXEL-SHIFTED SCREEN GRAPHICS
; Screen characters are stable; sprite 0 and 7 are unaffected.
; ----------------------------------------------------------------------
; ROUTINE redraw_aliens
; WHAT: Copies live display to shadows, erases all old three-cell footprints.
; WHY: Erasing and drawing in a shadow image reduces the chance of exposing a half-finished formation.
; HOW: Restores shields in shadow, draws all living aliens, then publishes dirty rows.
; HOW: Changes A X Y flags and $FB..$FE. Contains a raster wait; main-thread use only.
; ----------------------------------------------------------------------
redraw_aliens: ; Name the address of the next emitted byte; a label emits no bytes.
    jsr prepare_alien_buffer ; Copy live screen/colours before editing hidden RAM.
; Erase ONLY the 48 character cells occupied by the previous
; alien formation.  Never blank entire rows: shields and the
; background remain stable between frames.
    ldx #$00 ; Put the literal $00 in X; # selects a value; N/Z reflect it.
redraw_erase_next: ; Name the address of the next emitted byte; a label emits no bytes.
    lda alien_visible,x ; Read alien visible,x at the indexed element into A; update N/Z, preserve carry.
    beq redraw_erase_skip ; Branch to redraw_erase_skip when Z=1 (zero/equal); otherwise continue in sequence.
    lda alien_screen_lo,x ; Read alien screen lo,x at the indexed element into A; update N/Z, preserve carry.
    sta $fb ; Write A to first pointer low byte; a store leaves the CPU flags unchanged.
    lda alien_screen_hi,x ; Read alien screen hi,x at the indexed element into A; update N/Z, preserve carry.
    sta $fc ; Write A to first pointer high byte; a store leaves the CPU flags unchanged.
    jsr mark_old_row_dirty ; Remember which visible row needs publishing.
    ldy alien_screen_col,x ; Read alien screen col,x at the indexed element into Y; update N/Z, preserve carry.
    lda #$20 ; Put the literal $20 in A; # selects a value; N/Z reflect it.
    sta ($fb),y ; Write A through the pointer plus index; CPU flags stay unchanged.
    iny ; Increase Y by one modulo 256; set N/Z, preserve carry.
    sta ($fb),y ; Write A through the pointer plus index; CPU flags stay unchanged.
    iny ; Increase Y by one modulo 256; set N/Z, preserve carry.
    sta ($fb),y ; Third cell holds pixels shifted out of the second.
redraw_erase_skip: ; Name the address of the next emitted byte; a label emits no bytes.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #$18 ; Compare X with a value. Compare X with #$18; set N/Z/C without changing X; C means >= unsigned.
    bne redraw_erase_next ; Branch to redraw_erase_next when Z=0 (nonzero/not equal); otherwise continue in sequence.
    jsr draw_all_shields ; Restore shield health beneath the departing aliens.
; render_aliens also refreshes the cached collision coordinates.
    jsr render_aliens ; Call render_aliens; push a return address so the callee can return with RTS.
    jsr publish_alien_buffer ; Reveal complete rows after the beam has passed.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

draw_aliens: ; Name the address of the next emitted byte; a label emits no bytes.
    jmp redraw_aliens ; Continue at redraw_aliens without saving a subroutine return address.

; ----------------------------------------------------------------------
; ROUTINE render_aliens
; WHAT: Input logical arrays, shadow screen and row-address tables.
; WHY: Logical pixel positions must become glyph choices and screen addresses, with matching collision coordinates.
; HOW: Column=(X-24)/8; phase=(X-24)&7. Three glyphs per shifted alien.
; HOW: Caches displayed X and quantised Y for collision. Changes A X Y flags/pointers.
; ----------------------------------------------------------------------
render_aliens: ; Name the address of the next emitted byte; a label emits no bytes.
    ldx #$00 ; Put the literal $00 in X; # selects a value; N/Z reflect it.
render_next: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #0 ; Put the literal 0 in A; # selects a value; N/Z reflect it.
    sta alien_visible,x ; Write A to alien visible,x; a store leaves the CPU flags unchanged.
    lda alien_alive,x ; Read alien alive,x at the indexed element into A; update N/Z, preserve carry.
    bne render_alive ; Branch to render_alive when Z=0 (nonzero/not equal); otherwise continue in sequence.
    jmp render_skip ; Continue at render_skip without saving a subroutine return address.
render_alive: ; Name the address of the next emitted byte; a label emits no bytes.
; Convert VIC sprite coordinates to character cells.
; Y origin $30 ensures the first alien at Y=64 occupies screen row 2.
    sec ; Set carry so SBC subtracts without an extra borrow
    lda alien_x,x ; Read alien x,x at the indexed element into A; update N/Z, preserve carry.
    sbc #$18 ; Subtract #$18 and borrow from A. Subtract #$18 and the incoming borrow from A; C=1 means no borrow.
    sta alien_coord_lo ; Write A to alien coord lo; a store leaves the CPU flags unchanged.
    and #7 ; Keep only bits shared with #7; A and N/Z change; carry is preserved.
    sta alien_pixel_phase ; Low three bits choose a 0..7 pixel shifted picture.
    lda alien_x_hi,x ; Read alien x hi,x at the indexed element into A; update N/Z, preserve carry.
    sbc #$00 ; Subtract #$00 and borrow from A. Subtract #$00 and the incoming borrow from A; C=1 means no borrow.
    sta alien_coord_hi ; Write A to alien coord hi; a store leaves the CPU flags unchanged.
    ldy #$03 ; Put the literal $03 in Y; # selects a value; N/Z reflect it.
render_x_shift: ; Name the address of the next emitted byte; a label emits no bytes.
    lsr alien_coord_hi ; Shift bits right (divide by 2). Shift right with zero entering bit 7; old bit 0 goes to carry; update N/Z.
    ror alien_coord_lo ; Rotate bits right through carry. Rotate right through carry: old C enters bit 7, old bit 0 becomes C.
    dey ; Decrease Y by one modulo 256; set N/Z, preserve carry.
    bne render_x_shift ; Branch to render_x_shift when Z=0 (nonzero/not equal); otherwise continue in sequence.
    lda alien_coord_lo ; Read alien coord lo into A; update N/Z without changing carry.
    cmp #38 ; Compare A with #38; set N/Z/C without changing A; C means >= unsigned.
    bcc render_x_valid ; Jump to render_x_valid if carry is clear (unsigned less-than after CMP)
    jmp render_skip ; Continue at render_skip without saving a subroutine return address.
render_x_valid: ; Name the address of the next emitted byte; a label emits no bytes.
    sta alien_cell_x ; Write A to alien cell x; a store leaves the CPU flags unchanged.
; Shifted glyphs now display the exact logical X, including pixels >255.
    lda alien_x,x ; Read alien x,x at the indexed element into A; update N/Z, preserve carry.
    sta alien_draw_x,x ; Write A to alien draw x,x; a store leaves the CPU flags unchanged.
    lda alien_x_hi,x ; Read alien x hi,x at the indexed element into A; update N/Z, preserve carry.
    sta alien_draw_x_hi,x ; Write A to alien draw x hi,x; a store leaves the CPU flags unchanged.
    lda alien_y,x ; Read alien y,x at the indexed element into A; update N/Z, preserve carry.
    sec ; Set carry so SBC subtracts without an extra borrow
    sbc #$30 ; Subtract #$30 and borrow from A. Subtract #$30 and the incoming borrow from A; C=1 means no borrow.
    lsr ; Shift bits right (divide by 2). Shift right with zero entering bit 7; old bit 0 goes to carry; update N/Z.
    lsr ; Shift bits right (divide by 2). Shift right with zero entering bit 7; old bit 0 goes to carry; update N/Z.
    lsr ; Shift bits right (divide by 2). Shift right with zero entering bit 7; old bit 0 goes to carry; update N/Z.
    cmp #$14 ; Compare A with #$14; set N/Z/C without changing A; C means >= unsigned.
    bcc render_y_valid ; Jump to render_y_valid if carry is clear (unsigned less-than after CMP)
    jmp render_skip ; Continue at render_skip without saving a subroutine return address.
render_y_valid: ; Name the address of the next emitted byte; a label emits no bytes.
    tay ; Copy A to Y; N/Z reflect the copied byte.
    lda #1 ; Put the literal 1 in A; # selects a value; N/Z reflect it.
    sta dirty_rows,y ; Write A to dirty rows,y; a store leaves the CPU flags unchanged.
    tya ; Copy Y to A; N/Z reflect the copied byte.
; Visible character row 0 begins at VIC Y=50.
    pha ; Push A onto stack. Push A on the hardware stack; balance this save with a later PLA.
    asl ; Shift bits left (multiply by 2). Shift left with zero entering bit 0; old bit 7 goes to carry; update N/Z.
    asl ; Shift bits left (multiply by 2). Shift left with zero entering bit 0; old bit 7 goes to carry; update N/Z.
    asl ; Shift bits left (multiply by 2). Shift left with zero entering bit 0; old bit 7 goes to carry; update N/Z.
    clc ; Clear carry so ADC starts without adding an extra 1
    adc #50 ; Add #50 and carry to A; carry can extend a 16-bit value
    sta alien_draw_y,x ; Write A to alien draw y,x; a store leaves the CPU flags unchanged.
    lda #1 ; Put the literal 1 in A; # selects a value; N/Z reflect it.
    sta alien_visible,x ; Write A to alien visible,x; a store leaves the CPU flags unchanged.
    pla ; Pull A from stack. Pull a byte into A; update N/Z but leave carry unchanged.
    tay ; Copy A to Y. Copy A to Y; N/Z reflect the copied byte.
; 25 screen-row address tables, screen and colour RAM.
    lda screen_row_lo,y ; Read screen row lo,y at the indexed element into A; update N/Z, preserve carry.
    sta $fb ; Write A to first pointer low byte; a store leaves the CPU flags unchanged.
    lda screen_row_hi,y ; Read screen row hi,y at the indexed element into A; update N/Z, preserve carry.
    clc ; Clear carry before a new independent addition; do not break a byte-to-byte chain.
    adc #$4c ; $0400 becomes hidden screen at $5000.
    sta $fc ; Write A to first pointer high byte; a store leaves the CPU flags unchanged.
    lda color_row_lo,y ; Read color row lo,y at the indexed element into A; update N/Z, preserve carry.
    sta $fd ; Write A to second pointer low byte; a store leaves the CPU flags unchanged.
    lda screen_row_hi,y ; Read screen row hi,y at the indexed element into A; update N/Z, preserve carry.
    clc ; Clear carry before a new independent addition; do not break a byte-to-byte chain.
    adc #$50 ; Hidden colour values at $5400.. Add #$50 plus carry to A; C carries overflow into the next byte; set N/Z/V.
    sta $fe ; Write A to second pointer high byte; a store leaves the CPU flags unchanged.
; Cache the EXACT cells used to draw this alien. Next redraw
; erases only these cells, with no shield or full-row clearing.
    lda $fb ; Read first pointer low byte into A; update N/Z without changing carry.
    sta alien_screen_lo,x ; Write A to alien screen lo,x; a store leaves the CPU flags unchanged.
    lda $fc ; Read first pointer high byte into A; update N/Z without changing carry.
    sta alien_screen_hi,x ; Write A to alien screen hi,x; a store leaves the CPU flags unchanged.
    lda alien_cell_x ; Read alien cell x into A; update N/Z without changing carry.
    sta alien_screen_col,x ; Write A to alien screen col,x; a store leaves the CPU flags unchanged.
    ldy alien_cell_x ; Read alien cell x into Y; update N/Z without changing carry.
; Choose the design bank: squid $80, crab $98, octopus $b0.
; Add pixel phase * 3 to select its three-cell shifted image.
    txa ; Copy X to A; N/Z reflect the copied byte.
    cmp #8 ; Compare A with #8; set N/Z/C without changing A; C means >= unsigned.
    bcc render_shape_top ; Branch to render_shape_top when C=0 (unsigned less after compare); otherwise continue in sequence.
    cmp #16 ; Compare A with #16; set N/Z/C without changing A; C means >= unsigned.
    bcc render_shape_middle ; Branch to render_shape_middle when C=0 (unsigned less after compare); otherwise continue in sequence.
    lda #$b0 ; octopus: 8 phases x 3 cells. Put the literal $b0 in A; # selects a value; N/Z reflect it.
    bne render_shape_ready ; Branch to render_shape_ready when Z=0 (nonzero/not equal); otherwise continue in sequence.
render_shape_top: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$80 ; squid: 8 phases x 3 cells. Put the literal $80 in A; # selects a value; N/Z reflect it.
    bne render_shape_ready ; Branch to render_shape_ready when Z=0 (nonzero/not equal); otherwise continue in sequence.
render_shape_middle: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$98 ; crab: 8 phases x 3 cells. Put the literal $98 in A; # selects a value; N/Z reflect it.
render_shape_ready: ; Name the address of the next emitted byte; a label emits no bytes.
    sta shifted_glyph_base ; Write A to shifted glyph base; a store leaves the CPU flags unchanged.
    lda alien_pixel_phase ; Read alien pixel phase into A; update N/Z without changing carry.
    asl ; Shift left with zero entering bit 0; old bit 7 goes to carry; update N/Z.
    clc ; Clear carry before a new independent addition; do not break a byte-to-byte chain.
    adc alien_pixel_phase ; phase * 3 selects the first of three characters.
    adc shifted_glyph_base ; Add shifted_glyph_base plus carry to A; C carries overflow into the next byte; set N/Z/V.
    sta ($fb),y ; draw left half. Write A through the pointer plus index; CPU flags stay unchanged.
    clc ; Clear carry before a new independent addition; do not break a byte-to-byte chain.
    adc #1 ; right half is the next character code
    iny ; Increase Y by one modulo 256; set N/Z, preserve carry.
    sta ($fb),y ; draw right half. Write A through the pointer plus index; CPU flags stay unchanged.
    clc ; Clear carry before a new independent addition; do not break a byte-to-byte chain.
    adc #1 ; Add #1 plus carry to A; C carries overflow into the next byte; set N/Z/V.
    iny ; Increase Y by one modulo 256; set N/Z, preserve carry.
    sta ($fb),y ; Third character contains the overflow pixels.
; Different colour for each of the three alien rows.
; Indices 0-7: yellow, 8-15: cyan, 16-23: green.
    txa ; Copy X to A. Copy X to A; N/Z reflect the copied byte.
    cmp #8 ; Compare A with #8; set N/Z/C without changing A; C means >= unsigned.
    bcc render_colour_top ; Jump to render_colour_top if carry is clear (unsigned less-than after CMP)
    cmp #16 ; Compare A with #16; set N/Z/C without changing A; C means >= unsigned.
    bcc render_colour_middle ; Jump to render_colour_middle if carry is clear (unsigned less-than after CMP)
    lda #5 ; green: bottom row. Put the literal 5 in A; # selects a value; N/Z reflect it.
    bne render_colour_ready ; Branch to render_colour_ready when Z=0 (nonzero/not equal); otherwise continue in sequence.
render_colour_top: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #7 ; yellow: top row. Put the literal 7 in A; # selects a value; N/Z reflect it.
    bne render_colour_ready ; Branch to render_colour_ready when Z=0 (nonzero/not equal); otherwise continue in sequence.
render_colour_middle: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #3 ; cyan: middle row. Put the literal 3 in A; # selects a value; N/Z reflect it.
render_colour_ready: ; Name the address of the next emitted byte; a label emits no bytes.
    dey ; Return from third cell to first.. Decrease Y by one modulo 256; set N/Z, preserve carry.
    dey ; Decrease Y by one modulo 256; set N/Z, preserve carry.
    sta ($fd),y ; Write A through the pointer plus index; CPU flags stay unchanged.
    iny ; Increase Y by one modulo 256; set N/Z, preserve carry.
    sta ($fd),y ; Write A through the pointer plus index; CPU flags stay unchanged.
    iny ; Increase Y by one modulo 256; set N/Z, preserve carry.
    sta ($fd),y ; Write A through the pointer plus index; CPU flags stay unchanged.
render_skip: ; Name the address of the next emitted byte; a label emits no bytes.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #$18 ; Compare X with a value. Compare X with #$18; set N/Z/C without changing X; C means >= unsigned.
    beq render_finished ; Branch to render_finished when Z=1 (zero/equal); otherwise continue in sequence.
    jmp render_next ; Continue at render_next without saving a subroutine return address.
render_finished: ; Name the address of the next emitted byte; a label emits no bytes.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

alien_cell_x:   !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.

screen_row_lo: ; Name the address of the next emitted byte; a label emits no bytes.
!for .r, 0, 24 { !byte <(SCREEN + .r*40) } ; Emit these byte values in order; table and bitmap layout depends on them.
screen_row_hi: ; Name the address of the next emitted byte; a label emits no bytes.
!for .r, 0, 24 { !byte >(SCREEN + .r*40) } ; Emit these byte values in order; table and bitmap layout depends on them.
color_row_lo: ; Name the address of the next emitted byte; a label emits no bytes.
!for .r, 0, 24 { !byte <(COLOR + .r*40) } ; Emit these byte values in order; table and bitmap layout depends on them.
color_row_hi: ; Name the address of the next emitted byte; a label emits no bytes.
!for .r, 0, 24 { !byte >(COLOR + .r*40) } ; Emit these byte values in order; table and bitmap layout depends on them.

; GAME OVER

; ----------------------------------------------------------------------
; ROUTINE end_game
; WHAT: Finishes explosion updates, disables IRQs and sprites, clears display.
; WHY: Gameplay updates must stop before replay input starts a fresh initialisation path.
; HOW: Replay polls SCNKEY then GETIN with IRQs disabled. P jumps start.
; HOW: Does not return to BASIC or restore original machine settings.
; ----------------------------------------------------------------------
end_game: ; Name the address of the next emitted byte; a label emits no bytes.
; Keep the final explosion visible for its remaining frames.
; The raster IRQ continues updating sprite 0 during this wait.
end_game_explosion_wait: ; Name the address of the next emitted byte; a label emits no bytes.
    lda explosion_timer ; Read explosion timer into A; update N/Z without changing carry.
    beq end_game_stop ; Branch to end_game_stop when Z=1 (zero/equal); otherwise continue in sequence.
    lda frame_count ; Read IRQ frame counter into A; update N/Z without changing carry.
end_game_wait_frame: ; Name the address of the next emitted byte; a label emits no bytes.
    cmp frame_count ; Compare A with frame_count; set N/Z/C without changing A; C means >= unsigned.
    beq end_game_wait_frame ; Branch to end_game_wait_frame when Z=1 (zero/equal); otherwise continue in sequence.
    jsr update_explosion_and_sound ; Call update_explosion_and_sound; push a return address so the callee can return with RTS.
    jmp end_game_explosion_wait ; Continue at end_game_explosion_wait without saving a subroutine return address.
end_game_stop: ; Name the address of the next emitted byte; a label emits no bytes.
; Stop raster IRQs and sprites, play the game-over sound, then show a
; static message. This loop deliberately keeps the game-over screen up.
    sei ; Prevent further IRQ processing. Mask normal IRQ service while shared setup is incomplete; NMI is separate.

    lda #$00 ; Put the literal $00 in A; # selects a value; N/Z reflect it.
    sta $d01a ; Disable VIC raster IRQ. Write A to VIC interrupt enables; a store leaves the CPU flags unchanged.
    sta $d015 ; Disable all sprites. Write A to sprite enable mask; a store leaves the CPU flags unchanged.
    sta $d01b ; Disable sprite/background priority. Write A to $d01b; a store leaves the CPU flags unchanged.

    lda #$01 ; Put the literal $01 in A; # selects a value; N/Z reflect it.
    sta $d019 ; Acknowledge pending raster IRQ. Write A to VIC interrupt status/acknowledge; a store leaves the CPU flags unchanged.

    jsr sound_gameover ; Call sound_gameover; push a return address so the callee can return with RTS.
    jsr clear_screen ; Call clear_screen; push a return address so the callee can return with RTS.

    ldx #$00 ; Put the literal $00 in X; # selects a value; N/Z reflect it.

gameover_loop: ; Name the address of the next emitted byte; a label emits no bytes.
    lda gameover_msg,x ; Read gameover msg,x at the indexed element into A; update N/Z, preserve carry.
    beq gameover_done ; Branch to gameover_done when Z=1 (zero/equal); otherwise continue in sequence.

    sta SCREEN+12*40+6,x ; Write A to SCREEN+12*40+6,x; a store leaves the CPU flags unchanged.
    lda #$02 ; Put the literal $02 in A; # selects a value; N/Z reflect it.
    sta COLOR+12*40+6,x ; Write A to COLOR+12*40+6,x; a store leaves the CPU flags unchanged.

    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    bne gameover_loop ; Branch to gameover_loop when Z=0 (nonzero/not equal); otherwise continue in sequence.

gameover_done: ; Name the address of the next emitted byte; a label emits no bytes.
; IRQs are disabled above, so the KERNAL's regular keyboard
; interrupt is no longer scanning the keys. Poll the keyboard
; manually with SCNKEY, then read the key queue with GETIN.
gameover_wait_for_p: ; Name the address of the next emitted byte; a label emits no bytes.
    jsr $ff9f ; KERNAL SCNKEY: scan keyboard matrix
    jsr $ffe4 ; KERNAL GETIN: retrieve scanned key. Call $ffe4; push a return address so the callee can return with RTS.
    cmp #'p' ; Compare A with #'p'; set N/Z/C without changing A; C means >= unsigned.
    beq gameover_restart ; Branch to gameover_restart when Z=1 (zero/equal); otherwise continue in sequence.
    cmp #'P' ; Compare A with #'P'; set N/Z/C without changing A; C means >= unsigned.
    bne gameover_wait_for_p ; Branch to gameover_wait_for_p when Z=0 (nonzero/not equal); otherwise continue in sequence.

gameover_restart: ; Name the address of the next emitted byte; a label emits no bytes.
; START resets lives, score, aliens, shields, bullets and SID,
; then installs the raster IRQ again for a fresh game.
    jmp start ; Continue at start without saving a subroutine return address.


; SID SOUND EFFECTS
; Use SID voice 1 ($D400-$D406) for broad emulator compatibility.
; $D400/$D401 = frequency, $D404 = waveform/gate,
; $D405 = attack/decay, $D406 = sustain/release, $D418 = volume.

; ----------------------------------------------------------------------
; ROUTINE sound_init
; WHAT: Event-driven SID register writes; see the following constants for exact waveform.
; WHY: A known voice-control and master-volume state makes later sound events predictable.
; HOW: Voice 1 except enemy fire on voice 2. Events on the same voice replace earlier settings.
; HOW: Changes A and flags. sound_enemy_fire also starts an eight-update release timer.
; ----------------------------------------------------------------------
sound_init: ; Name the address of the next emitted byte; a label emits no bytes.
; Set master volume and silence voice 1.
    lda #$00 ; Put the literal $00 in A; # selects a value; N/Z reflect it.
    sta $d404 ; Gate off, no waveform selected. Write A to $d404; a store leaves the CPU flags unchanged.
    sta $d405 ; Attack/decay envelope. Write A to $d405; a store leaves the CPU flags unchanged.
    sta $d406 ; Sustain/release envelope. Write A to $d406; a store leaves the CPU flags unchanged.
    lda #$00 ; Put the literal $00 in A; # selects a value; N/Z reflect it.
    sta $d40b ; Voice 2 off initially. Write A to $d40b; a store leaves the CPU flags unchanged.
    lda #$0f ; Put the literal $0f in A; # selects a value; N/Z reflect it.
    sta $d418 ; Master volume maximum, filter input disabled
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; FIRE SOUND: high-pitched triangle-wave laser.
; ----------------------------------------------------------------------
; ROUTINE sound_fire
; WHAT: Event-driven SID register writes; see the following constants for exact waveform.
; WHY: Firing should produce an immediate audible response without stopping the game loop.
; HOW: Voice 1 except enemy fire on voice 2. Events on the same voice replace earlier settings.
; HOW: Changes A and flags. sound_enemy_fire also starts an eight-update release timer.
; ----------------------------------------------------------------------
sound_fire: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$00 ; Put the literal $00 in A; # selects a value; N/Z reflect it.
    sta $d404 ; Gate off first, retrigger envelope. Write A to $d404; a store leaves the CPU flags unchanged.
    lda #$c0 ; Put the literal $c0 in A; # selects a value; N/Z reflect it.
    sta $d400 ; Voice 1 frequency low byte. Write A to $d400; a store leaves the CPU flags unchanged.
    lda #$35 ; Put the literal $35 in A; # selects a value; N/Z reflect it.
    sta $d401 ; Voice 1 frequency high byte. Write A to $d401; a store leaves the CPU flags unchanged.
    lda #$09 ; Put the literal $09 in A; # selects a value; N/Z reflect it.
    sta $d405 ; Fast attack, short decay. Write A to $d405; a store leaves the CPU flags unchanged.
    lda #$08 ; Put the literal $08 in A; # selects a value; N/Z reflect it.
    sta $d406 ; No sustain; short release. Write A to $d406; a store leaves the CPU flags unchanged.
    lda #$11 ; Put the literal $11 in A; # selects a value; N/Z reflect it.
    sta $d404 ; Triangle waveform + gate on. Write A to $d404; a store leaves the CPU flags unchanged.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; ALIEN HIT SOUND: lower sawtooth blast.
; ----------------------------------------------------------------------
; ROUTINE sound_hit
; WHAT: Event-driven SID register writes; see the following constants for exact waveform.
; WHY: A distinct effect confirms that a shot removed an alien.
; HOW: Voice 1 except enemy fire on voice 2. Events on the same voice replace earlier settings.
; HOW: Changes A and flags. sound_enemy_fire also starts an eight-update release timer.
; ----------------------------------------------------------------------
sound_hit: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$00 ; Put the literal $00 in A; # selects a value; N/Z reflect it.
    sta $d404 ; Gate off to retrigger envelope. Write A to $d404; a store leaves the CPU flags unchanged.
    lda #$40 ; Put the literal $40 in A; # selects a value; N/Z reflect it.
    sta $d400 ; Lower frequency, low byte. Write A to $d400; a store leaves the CPU flags unchanged.
    lda #$18 ; Put the literal $18 in A; # selects a value; N/Z reflect it.
    sta $d401 ; Frequency high byte. Write A to $d401; a store leaves the CPU flags unchanged.
    lda #$08 ; Put the literal $08 in A; # selects a value; N/Z reflect it.
    sta $d405 ; Quick attack and decay. Write A to $d405; a store leaves the CPU flags unchanged.
    lda #$08 ; Put the literal $08 in A; # selects a value; N/Z reflect it.
    sta $d406 ; Short release. Write A to $d406; a store leaves the CPU flags unchanged.
    lda #$21 ; Put the literal $21 in A; # selects a value; N/Z reflect it.
    sta $d404 ; Sawtooth waveform + gate on. Write A to $d404; a store leaves the CPU flags unchanged.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; GAME OVER SOUND: low noise burst.
; ----------------------------------------------------------------------
; ROUTINE sound_player_hit
; WHAT: Event-driven SID register writes; see the following constants for exact waveform.
; WHY: The player needs audible feedback that a life was lost.
; HOW: Voice 1 except enemy fire on voice 2. Events on the same voice replace earlier settings.
; HOW: Changes A and flags. sound_enemy_fire also starts an eight-update release timer.
; ----------------------------------------------------------------------
sound_player_hit: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #0 ; Put the literal 0 in A; # selects a value; N/Z reflect it.
    sta $d404 ; Write A to $d404; a store leaves the CPU flags unchanged.
    lda #$50 ; Put the literal $50 in A; # selects a value; N/Z reflect it.
    sta $d400 ; Write A to $d400; a store leaves the CPU flags unchanged.
    lda #$06 ; Put the literal $06 in A; # selects a value; N/Z reflect it.
    sta $d401 ; Write A to $d401; a store leaves the CPU flags unchanged.
    lda #$05 ; Put the literal $05 in A; # selects a value; N/Z reflect it.
    sta $d405 ; Write A to $d405; a store leaves the CPU flags unchanged.
    lda #$05 ; Put the literal $05 in A; # selects a value; N/Z reflect it.
    sta $d406 ; Write A to $d406; a store leaves the CPU flags unchanged.
    lda #$81 ; Put the literal $81 in A; # selects a value; N/Z reflect it.
    sta $d404 ; Write A to $d404; a store leaves the CPU flags unchanged.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; ALIEN FIRE: a brief descending/noisy laser from SID voice 2.
; Voice 2 is independent of voice 1 used for player shots and hits.
; ----------------------------------------------------------------------
; ROUTINE sound_enemy_fire
; WHAT: Event-driven SID register writes; see the following constants for exact waveform.
; WHY: A separate SID voice lets enemy fire sound without replacing the player's voice immediately.
; HOW: Voice 1 except enemy fire on voice 2. Events on the same voice replace earlier settings.
; HOW: Changes A and flags. sound_enemy_fire also starts an eight-update release timer.
; ----------------------------------------------------------------------
sound_enemy_fire: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$00 ; Put the literal $00 in A; # selects a value; N/Z reflect it.
    sta $d40b ; Gate off before retrigger. Write A to $d40b; a store leaves the CPU flags unchanged.
    lda #$60 ; Put the literal $60 in A; # selects a value; N/Z reflect it.
    sta $d407 ; Voice 2 frequency low. Write A to $d407; a store leaves the CPU flags unchanged.
    lda #$27 ; Put the literal $27 in A; # selects a value; N/Z reflect it.
    sta $d408 ; Voice 2 frequency high. Write A to $d408; a store leaves the CPU flags unchanged.
    lda #$02 ; Put the literal $02 in A; # selects a value; N/Z reflect it.
    sta $d40c ; Fast attack, short decay. Write A to $d40c; a store leaves the CPU flags unchanged.
    lda #$00 ; Put the literal $00 in A; # selects a value; N/Z reflect it.
    sta $d40d ; Zero sustain, fast release. Write A to $d40d; a store leaves the CPU flags unchanged.
    lda #$81 ; Put the literal $81 in A; # selects a value; N/Z reflect it.
    sta $d40b ; Noise + gate on. Write A to $d40b; a store leaves the CPU flags unchanged.
    lda #$08 ; Put the literal $08 in A; # selects a value; N/Z reflect it.
    sta enemy_sound_timer ; Write A to enemy sound timer; a store leaves the CPU flags unchanged.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; ----------------------------------------------------------------------
; ROUTINE sound_gameover
; WHAT: Event-driven SID register writes; see the following constants for exact waveform.
; WHY: The transition to the replay screen needs its own sound event.
; HOW: Voice 1 except enemy fire on voice 2. Events on the same voice replace earlier settings.
; HOW: Changes A and flags. sound_enemy_fire also starts an eight-update release timer.
; ----------------------------------------------------------------------
sound_gameover: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$00 ; Put the literal $00 in A; # selects a value; N/Z reflect it.
    sta $d404 ; Reset previous sound. Write A to $d404; a store leaves the CPU flags unchanged.
    lda #$30 ; Put the literal $30 in A; # selects a value; N/Z reflect it.
    sta $d400 ; Low frequency, low byte. Write A to $d400; a store leaves the CPU flags unchanged.
    lda #$08 ; Put the literal $08 in A; # selects a value; N/Z reflect it.
    sta $d401 ; Low frequency, high byte. Write A to $d401; a store leaves the CPU flags unchanged.
    lda #$08 ; Put the literal $08 in A; # selects a value; N/Z reflect it.
    sta $d405 ; Fast attack/decay. Write A to $d405; a store leaves the CPU flags unchanged.
    lda #$08 ; Put the literal $08 in A; # selects a value; N/Z reflect it.
    sta $d406 ; Short release. Write A to $d406; a store leaves the CPU flags unchanged.
    lda #$81 ; Put the literal $81 in A; # selects a value; N/Z reflect it.
    sta $d404 ; Noise waveform + gate on. Write A to $d404; a store leaves the CPU flags unchanged.
    rts ; Pull the saved call address and add one; resume after the calling JSR.


; FOUR DESTRUCTIBLE DEFENCE BASES (character cells)
; Each shield has five columns and two rows, placed at rows 17-18.
; Durability: 3 = solid, 2 = damaged, 1 = almost gone, 0 = hole.
; Both friendly and enemy shots carve a hole in the impacted cell.
; The state persists between waves, as in the arcade game.
; ----------------------------------------------------------------------
; ROUTINE init_shields
; WHAT: Initialises all 40 shield_health entries to 3 then draws them.
; WHY: A new game must restore every shield cell's health before drawing it.
; HOW: Called by new-game startup, not next_wave.
; HOW: Changes A X Y flags and pointers through drawing helpers.
; ----------------------------------------------------------------------
init_shields: ; Name the address of the next emitted byte; a label emits no bytes.
    ldx #0 ; Put the literal 0 in X; # selects a value; N/Z reflect it.
shield_init_loop: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #3 ; Put the literal 3 in A; # selects a value; N/Z reflect it.
    sta shield_health,x ; Write A to shield health,x; a store leaves the CPU flags unchanged.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #40 ; Compare X with a value. Compare X with #40; set N/Z/C without changing X; C means >= unsigned.
    bne shield_init_loop ; Branch to shield_init_loop when Z=0 (nonzero/not equal); otherwise continue in sequence.
    jmp draw_all_shields ; Continue at draw_all_shields without saving a subroutine return address.

; ----------------------------------------------------------------------
; ROUTINE draw_all_shields
; WHAT: Draws all 40 shield cells using health, columns and shadow_mode.
; WHY: A formation redraw must restore shield cells that old alien footprints may have erased in the shadow image.
; HOW: Live rows 17/18 or corresponding hidden buffers.
; HOW: Changes A X Y flags and $FB..$FE. Leaves X=40.
; ----------------------------------------------------------------------
draw_all_shields: ; Name the address of the next emitted byte; a label emits no bytes.
    ldx #0 ; Put the literal 0 in X; # selects a value; N/Z reflect it.
shield_draw_loop: ; Name the address of the next emitted byte; a label emits no bytes.
    jsr draw_shield_cell ; Call draw_shield_cell; push a return address so the callee can return with RTS.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx #40 ; Compare X with a value. Compare X with #40; set N/Z/C without changing X; C means >= unsigned.
    bne shield_draw_loop ; Branch to shield_draw_loop when Z=0 (nonzero/not equal); otherwise continue in sequence.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; ----------------------------------------------------------------------
; ROUTINE draw_shield_cell
; WHAT: Input X=0..39 selects shield cell and health.
; WHY: One health value should choose one consistent damage picture in either live or shadow memory.
; HOW: shadow_mode selects live or hidden targets. Writes glyph and green colour.
; HOW: Restores X; changes A Y flags and $FB..$FE.
; ----------------------------------------------------------------------
draw_shield_cell: ; Name the address of the next emitted byte; a label emits no bytes.
; Input X = cell index 0..39. Preserve X.
    txa ; Copy X to A. Copy X to A; N/Z reflect the copied byte.
    pha ; Push A onto stack. Push A on the hardware stack; balance this save with a later PLA.
    cpx #20 ; Compare X with a value. Compare X with #20; set N/Z/C without changing X; C means >= unsigned.
    bcc shield_top_row ; Jump to shield_top_row if carry is clear (unsigned less-than after CMP)
    txa ; Copy X to A. Copy X to A; N/Z reflect the copied byte.
    sec ; Set carry so SBC subtracts without an extra borrow
    sbc #20 ; Subtract #20 and borrow from A. Subtract #20 and the incoming borrow from A; C=1 means no borrow.
    tax ; Copy A to X. Copy A to X; N/Z reflect the copied byte.
    lda #<(SCREEN+18*40) ; Put the literal <(SCREEN+18*40) in A; # selects a value; N/Z reflect it.
    sta ptr ; Write A to screen pointer low byte; a store leaves the CPU flags unchanged.
    lda #>(SCREEN+18*40) ; Put the literal >(SCREEN+18*40) in A; # selects a value; N/Z reflect it.
    sta ptr+1 ; Write A to screen pointer high byte; a store leaves the CPU flags unchanged.
    lda #<(COLOR+18*40) ; Put the literal <(COLOR+18*40) in A; # selects a value; N/Z reflect it.
    sta color_ptr ; Write A to colour pointer low byte; a store leaves the CPU flags unchanged.
    lda #>(COLOR+18*40) ; Put the literal >(COLOR+18*40) in A; # selects a value; N/Z reflect it.
    sta color_ptr+1 ; Write A to colour pointer high byte; a store leaves the CPU flags unchanged.
    jmp shield_draw_address ; Continue at shield_draw_address without saving a subroutine return address.
shield_top_row: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #<(SCREEN+17*40) ; Put the literal <(SCREEN+17*40) in A; # selects a value; N/Z reflect it.
    sta ptr ; Write A to screen pointer low byte; a store leaves the CPU flags unchanged.
    lda #>(SCREEN+17*40) ; Put the literal >(SCREEN+17*40) in A; # selects a value; N/Z reflect it.
    sta ptr+1 ; Write A to screen pointer high byte; a store leaves the CPU flags unchanged.
    lda #<(COLOR+17*40) ; Put the literal <(COLOR+17*40) in A; # selects a value; N/Z reflect it.
    sta color_ptr ; Write A to colour pointer low byte; a store leaves the CPU flags unchanged.
    lda #>(COLOR+17*40) ; Put the literal >(COLOR+17*40) in A; # selects a value; N/Z reflect it.
    sta color_ptr+1 ; Write A to colour pointer high byte; a store leaves the CPU flags unchanged.
shield_draw_address: ; Name the address of the next emitted byte; a label emits no bytes.
    lda shadow_mode ; Read shadow mode into A; update N/Z without changing carry.
    beq shield_draw_live ; Branch to shield_draw_live when Z=1 (zero/equal); otherwise continue in sequence.
    lda ptr+1 ; Read screen pointer high byte into A; update N/Z without changing carry.
    clc ; Clear carry before a new independent addition; do not break a byte-to-byte chain.
    adc #$4c ; Add #$4c plus carry to A; C carries overflow into the next byte; set N/Z/V.
    sta ptr+1 ; Write A to screen pointer high byte; a store leaves the CPU flags unchanged.
    lda color_ptr+1 ; Read colour pointer high byte into A; update N/Z without changing carry.
    sec ; Set carry before a new subtraction, meaning there is no incoming borrow.
    sbc #$84 ; $d8 -> $54, preserving the low page offset.
    sta color_ptr+1 ; Write A to colour pointer high byte; a store leaves the CPU flags unchanged.
shield_draw_live: ; Name the address of the next emitted byte; a label emits no bytes.
    lda shield_columns,x ; Read shield columns,x at the indexed element into A; update N/Z, preserve carry.
    tay ; Copy A to Y. Copy A to Y; N/Z reflect the copied byte.
    pla ; Pull A from stack. Pull a byte into A; update N/Z but leave carry unchanged.
    tax ; Copy A to X. Copy A to X; N/Z reflect the copied byte.
    lda shield_health,x ; Read shield health,x at the indexed element into A; update N/Z, preserve carry.
    beq shield_cell_empty ; Branch to shield_cell_empty when Z=1 (zero/equal); otherwise continue in sequence.
    cmp #3 ; Compare A with #3; set N/Z/C without changing A; C means >= unsigned.
    beq shield_cell_full ; Branch to shield_cell_full when Z=1 (zero/equal); otherwise continue in sequence.
    cmp #2 ; Compare A with #2; set N/Z/C without changing A; C means >= unsigned.
    beq shield_cell_damaged ; Branch to shield_cell_damaged when Z=1 (zero/equal); otherwise continue in sequence.
    lda #$6a ; Crumbling pattern. Put the literal $6a in A; # selects a value; N/Z reflect it.
    bne shield_cell_write ; Branch to shield_cell_write when Z=0 (nonzero/not equal); otherwise continue in sequence.
shield_cell_full: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$68 ; Solid block glyph. Put the literal $68 in A; # selects a value; N/Z reflect it.
    bne shield_cell_write ; Branch to shield_cell_write when Z=0 (nonzero/not equal); otherwise continue in sequence.
shield_cell_damaged: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$69 ; Partially broken glyph. Put the literal $69 in A; # selects a value; N/Z reflect it.
    bne shield_cell_write ; Branch to shield_cell_write when Z=0 (nonzero/not equal); otherwise continue in sequence.
shield_cell_empty: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #$20 ; Put the literal $20 in A; # selects a value; N/Z reflect it.
shield_cell_write: ; Name the address of the next emitted byte; a label emits no bytes.
    sta (ptr),y ; Write A through the pointer plus index; CPU flags stay unchanged.
    lda #$05 ; Green. Put the literal $05 in A; # selects a value; N/Z reflect it.
    sta (color_ptr),y ; Write A through the pointer plus index; CPU flags stay unchanged.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; ----------------------------------------------------------------------
; ROUTINE shield_test_shot
; WHAT: Inputs shield_shot_x/hi and shield_shot_y sample a point.
; WHY: Both sides need the same point-to-cell damage rule and a simple hit result in carry.
; HOW: Returns C=1 when a healthy cell absorbs shot, C=0 otherwise.
; HOW: Preserves X and Y; changes A flags pointers and scratch bytes. Decrements health.
; ----------------------------------------------------------------------
shield_test_shot: ; Name the address of the next emitted byte; a label emits no bytes.
; Inputs: shot's 16-bit sprite X, and actual bolt pixel Y.
; Output: carry SET if a shield cell absorbed the shot.
; No sprite or player registers are modified; X and Y are preserved.
    txa ; Copy X to A. Copy X to A; N/Z reflect the copied byte.
    pha ; Push A onto stack. Push A on the hardware stack; balance this save with a later PLA.
    tya ; Copy Y to A. Copy Y to A; N/Z reflect the copied byte.
    pha ; Push A onto stack. Push A on the hardware stack; balance this save with a later PLA.
    lda shield_shot_y ; Read shield shot y into A; update N/Z without changing carry.
    cmp #186 ; row 17 begins at raster 186. Compare A with #186; set N/Z/C without changing A; C means >= unsigned.
    bcc shield_no_hit ; Jump to shield_no_hit if carry is clear (unsigned less-than after CMP)
    cmp #202 ; row 18 ends at raster 201. Compare A with #202; set N/Z/C without changing A; C means >= unsigned.
    bcs shield_no_hit ; Jump to shield_no_hit if carry is set (unsigned >= after CMP)
; Correct 16-bit VIC X to character column conversion.
; VIC text cell 0 begins at sprite X=24.
    sec ; Set carry so SBC subtracts without an extra borrow
    lda shield_shot_x ; Read shield shot x into A; update N/Z without changing carry.
    sbc #24 ; Subtract #24 and borrow from A. Subtract #24 and the incoming borrow from A; C=1 means no borrow.
    sta shield_col_lo ; Write A to shield col lo; a store leaves the CPU flags unchanged.
    lda shield_shot_hi ; Read shield shot hi into A; update N/Z without changing carry.
    sbc #0 ; Subtract #0 and borrow from A. Subtract #0 and the incoming borrow from A; C=1 means no borrow.
    bcc shield_no_hit ; Jump to shield_no_hit if carry is clear (unsigned less-than after CMP)
    sta shield_col_hi ; Write A to shield col hi; a store leaves the CPU flags unchanged.
    ldx #3 ; Put the literal 3 in X; # selects a value; N/Z reflect it.
shield_shift_x: ; Name the address of the next emitted byte; a label emits no bytes.
    lsr shield_col_hi ; Shift bits right (divide by 2). Shift right with zero entering bit 7; old bit 0 goes to carry; update N/Z.
    ror shield_col_lo ; Rotate bits right through carry. Rotate right through carry: old C enters bit 7, old bit 0 becomes C.
    dex ; Decrease X by one modulo 256; set N/Z, preserve carry.
    bne shield_shift_x ; Branch to shield_shift_x when Z=0 (nonzero/not equal); otherwise continue in sequence.
    lda shield_col_hi ; Read shield col hi into A; update N/Z without changing carry.
    bne shield_no_hit ; Branch to shield_no_hit when Z=0 (nonzero/not equal); otherwise continue in sequence.
    lda shield_col_lo ; Read shield col lo into A; update N/Z without changing carry.
    cmp #40 ; Compare A with #40; set N/Z/C without changing A; C means >= unsigned.
    bcs shield_no_hit ; Jump to shield_no_hit if carry is set (unsigned >= after CMP)
    sta shield_target_col ; Write A to shield target col; a store leaves the CPU flags unchanged.
    lda shield_shot_y ; Read shield shot y into A; update N/Z without changing carry.
    cmp #194 ; Compare A with #194; set N/Z/C without changing A; C means >= unsigned.
    bcc shield_shot_top ; Jump to shield_shot_top if carry is clear (unsigned less-than after CMP)
    ldx #20 ; Put the literal 20 in X; # selects a value; N/Z reflect it.
    lda #40 ; Put the literal 40 in A; # selects a value; N/Z reflect it.
    sta shield_scan_end ; Write A to shield scan end; a store leaves the CPU flags unchanged.
    bne shield_scan ; Branch to shield_scan when Z=0 (nonzero/not equal); otherwise continue in sequence.
shield_shot_top: ; Name the address of the next emitted byte; a label emits no bytes.
    ldx #0 ; Put the literal 0 in X; # selects a value; N/Z reflect it.
    lda #20 ; Put the literal 20 in A; # selects a value; N/Z reflect it.
    sta shield_scan_end ; Write A to shield scan end; a store leaves the CPU flags unchanged.
shield_scan: ; Name the address of the next emitted byte; a label emits no bytes.
    lda shield_columns,x ; Read shield columns,x at the indexed element into A; update N/Z, preserve carry.
    cmp shield_target_col ; Compare A with shield_target_col; set N/Z/C without changing A; C means >= unsigned.
    bne shield_scan_next ; Branch to shield_scan_next when Z=0 (nonzero/not equal); otherwise continue in sequence.
    lda shield_health,x ; Read shield health,x at the indexed element into A; update N/Z, preserve carry.
    beq shield_no_hit ; Branch to shield_no_hit when Z=1 (zero/equal); otherwise continue in sequence.
    dec shield_health,x ; Decrease shield health,x by one modulo 256; set N/Z, preserve carry.
    jsr draw_shield_cell ; Call draw_shield_cell; push a return address so the callee can return with RTS.
    sec ; Set carry so SBC subtracts without an extra borrow
    bcs shield_test_return ; Jump to shield_test_return if carry is set (unsigned >= after CMP)
shield_scan_next: ; Name the address of the next emitted byte; a label emits no bytes.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    cpx shield_scan_end ; Compare X with a value. Compare X with shield_scan_end; set N/Z/C without changing X; C means >= unsigned.
    bne shield_scan ; Branch to shield_scan when Z=0 (nonzero/not equal); otherwise continue in sequence.
shield_no_hit: ; Name the address of the next emitted byte; a label emits no bytes.
    clc ; Clear carry so ADC starts without adding an extra 1
shield_test_return: ; Name the address of the next emitted byte; a label emits no bytes.
    pla ; Pull A from stack. Pull a byte into A; update N/Z but leave carry unchanged.
    tay ; Copy A to Y. Copy A to Y; N/Z reflect the copied byte.
    pla ; Pull A from stack. Pull a byte into A; update N/Z but leave carry unchanged.
    tax ; Copy A to X. Copy A to X; N/Z reflect the copied byte.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; Shield screen columns: 4 bases x 5 cells, repeated for two rows.
shield_columns: ; Name the address of the next emitted byte; a label emits no bytes.
    !byte 4,5,6,7,8, 13,14,15,16,17, 22,23,24,25,26, 31,32,33,34,35 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 4,5,6,7,8, 13,14,15,16,17, 22,23,24,25,26, 31,32,33,34,35 ; Emit these byte values in order; table and bitmap layout depends on them.
shield_health:     !fill 40,0 ; Emit the requested number of initial bytes for this array or data block.
shield_shot_x:     !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
shield_shot_hi:    !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
shield_shot_y:     !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
shield_col_lo:     !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
shield_col_hi:     !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
shield_target_col: !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
shield_scan_end:   !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.

; VARIABLES
; State bytes used by the main loop, IRQ handler, collision checks and HUD.
; The three alien arrays each contain 24 entries, one per alien.

; Three enemy bolt objects use physical sprites 1, 2 and 3.
enemy_x:          !fill 3,0 ; Emit the requested number of initial bytes for this array or data block.
enemy_x_hi:       !fill 3,0 ; Emit the requested number of initial bytes for this array or data block.
enemy_y:          !fill 3,0 ; Emit the requested number of initial bytes for this array or data block.
enemy_active:     !fill 3,0 ; Emit the requested number of initial bytes for this array or data block.
enemy_bits:       !byte $02,$04,$08 ; Emit these byte values in order; table and bitmap layout depends on them.
enemy_slot:       !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
enemy_delta:      !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
enemy_delta_hi:   !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
enemy_fire_clock: !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
enemy_fire_index: !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
sprite_enable_work: !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
sprite_msb_work:    !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
invulnerable:     !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
explosion_timer: !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
enemy_sound_timer: !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
lives:            !byte 3 ; Emit these byte values in order; table and bitmap layout depends on them.

input_joystick: !byte $ff ; Emit these byte values in order; table and bitmap layout depends on them.
input_keys:     !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
input_actions:  !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.

player_x:       !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
player_x_hi:    !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
bullet_x:       !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
bullet_x_hi:    !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
bullet_y:       !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
bullet_active:  !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.

direction:      !byte 2 ; Emit these byte values in order; table and bitmap layout depends on them.
frame_count:    !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
old_frame:      !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
game_ticks:     !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
game_over:      !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.

irq_phase:      !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
row_base:       !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
hit_edge:       !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
temp_x:         !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
temp_col:       !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
temp_ones:      !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
score:          !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
score_hi:       !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
score_work_lo:  !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
score_work_hi:  !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
collision_left_hi: !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
collision_bullet_lo: !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
collision_bullet_hi: !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
collision_delta: !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
aliens_remaining: !byte 24 ; Emit these byte values in order; table and bitmap layout depends on them.
wave_number:    !byte 0 ; Current wave, 1..255 (wraps after 255)
wave_work:      !byte 0 ; Temporary copy for decimal conversion

alien_x:        !fill 24,0 ; Emit the requested number of initial bytes for this array or data block.
alien_x_hi:     !fill 24,0 ; Emit the requested number of initial bytes for this array or data block.
alien_coord_lo: !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
alien_coord_hi: !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
alien_y:        !fill 24,0 ; Emit the requested number of initial bytes for this array or data block.
alien_alive:    !fill 24,0 ; Emit the requested number of initial bytes for this array or data block.
; These arrays are refreshed by render_aliens, so hit detection cannot
; disagree with the pixel-shifted X and character-row-aligned Y display.
alien_visible:   !fill 24,0 ; Emit the requested number of initial bytes for this array or data block.
alien_draw_x:    !fill 24,0 ; Emit the requested number of initial bytes for this array or data block.
alien_draw_x_hi: !fill 24,0 ; Emit the requested number of initial bytes for this array or data block.
alien_draw_y:    !fill 24,0 ; Emit the requested number of initial bytes for this array or data block.
alien_screen_lo:  !fill 24,0 ; Emit the requested number of initial bytes for this array or data block.
alien_screen_hi:  !fill 24,0 ; Emit the requested number of initial bytes for this array or data block.
alien_screen_col: !fill 24,0 ; Emit the requested number of initial bytes for this array or data block.

title_text: ; Name the address of the next emitted byte; a label emits no bytes.
    !byte $20,$13,$10,$01,$03,$05,$20 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $09,$0e,$16,$01,$04,$05,$12,$13 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $20,$00 ; Emit these byte values in order; table and bitmap layout depends on them.

score_text: ; Name the address of the next emitted byte; a label emits no bytes.
    !byte $13,$03,$0f,$12,$05,$3a,$20,$30,$30 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $20,$20,$20,$01,$2f,$04,$20 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $0d,$0f,$16,$05,$20,$20 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $13,$10,$01,$03,$05,$20 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $06,$09,$12,$05,$20,$20 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $11,$20,$11,$15,$09,$14,$00 ; Emit these byte values in order; table and bitmap layout depends on them.

lives_text: ; Name the address of the next emitted byte; a label emits no bytes.
    !byte $0c,$09,$16,$05,$13,$3a,$20 ; "LIVES: " screen codes. Emit these byte values in order; table and bitmap layout depends on them.

gameover_msg: ; Name the address of the next emitted byte; a label emits no bytes.
; Explicit screen codes (A=$01..Z=$1a), not PETSCII.
    !byte $07,$01,$0d,$05,$20,$0f,$16,$05 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $12,$20,$2d,$20,$10,$12,$05,$13 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $13,$20,$10,$20,$14,$0f,$20,$10 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $0c,$01,$19,$00 ; Emit these byte values in order; table and bitmap layout depends on them.

; SPRITE DATA
; Each VIC-II sprite occupies 64 bytes: 21 rows x 3 bytes (63 bytes),
; followed by one padding byte. Pointers $80/$81/$82 refer to $2000/$2040/$2080.

* = $2000 ; Place subsequent bytes at this address; this is an assembler origin.

; Alien: 24 x 21 pixels
alien_sprite: ; Name the address of the next emitted byte; a label emits no bytes.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,24,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,60,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,126,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 1,219,128 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 3,255,192 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 3,183,192 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 3,255,192 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 1,165,128 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 1,129,128 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,195,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,102,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.

; Player ship: pointer $81 = $2040
player_sprite: ; Name the address of the next emitted byte; a label emits no bytes.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,24,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,24,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,60,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,60,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,126,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,126,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 1,255,128 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 3,255,192 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 7,255,224 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 7,255,224 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 6,219,96 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 4,153,32 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 4,153,32 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 4,129,32 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.



; Bullet: pointer $82 = $2080
; Centered vertical line, 24 pixels wide.
bullet_sprite: ; Name the address of the next emitted byte; a label emits no bytes.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,24,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,24,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,24,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,24,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,24,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,24,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,24,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,24,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,24,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,24,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.


; Enemy shot: pointer $83 = $20C0. Narrow jagged laser bolt.
enemy_shot_sprite: ; Name the address of the next emitted byte; a label emits no bytes.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,24,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,24,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,60,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,24,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,24,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,60,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,24,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,24,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,60,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,24,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,24,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0,0,0 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.

; Explosion image: VIC sprite pointer $84 = $2100.
; Four-point burst and scattered sparks; 24x21 single-colour sprite.
* = $2100 ; Place subsequent bytes at this address; this is an assembler origin.
player_explosion_sprite: ; Name the address of the next emitted byte; a label emits no bytes.
    !byte %00000000,%00000000,%00000000 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %00000000,%00011000,%00000000 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %00000000,%10011001,%00000000 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %00000000,%01011010,%00000000 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %00000000,%00111100,%00000000 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %00000100,%00111100,%00100000 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %00000010,%11111111,%01000000 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %00000001,%11111111,%10000000 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %00000000,%11111111,%00000000 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %00000011,%11111111,%11000000 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %00000111,%11111111,%11100000 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %00000011,%11111111,%11000000 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %00000000,%11111111,%00000000 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %00000001,%11111111,%10000000 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %00000010,%11111111,%01000000 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %00000100,%00111100,%00100000 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %00000000,%00111100,%00000000 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %00000000,%01011010,%00000000 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %00000000,%10011001,%00000000 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %00000000,%00011000,%00000000 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte %00000000,%00000000,%00000000 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.

; SMOOTH RENDERING: READ THIS AFTER render_aliens
; Learning route: start -> main_loop -> read_keyboard (controls) ->
; update_bullet / move_aliens (physics) -> init_aliens (make_level) ->
; render_aliens (sprite_frame) -> sound_init / sound routines (music_tick).

; A 16-pixel picture shifted right needs THREE character cells, not two.
; Aliens use 24-pixel slots so their three-cell footprints cannot overlap.
; Each design has eight pre-shifted versions. Screen X chooses a cell;
; X AND 7 chooses the version within that cell. Thus a logical two-pixel
; move is also a visible two-pixel move, even across X=255.

; $5000/$5400 are hidden screen/colour workspaces, not VIC screen banks.
; We first copy the current display, erase old aliens there, restore the
; shields, then draw the new aliens there. Only affected rows are copied
; back. We wait until BELOW every affected row first. The VIC therefore
; never sees a blank formation between erase and draw. Colour RAM itself
; cannot be double-buffered; it is copied in the same safe time window.
; At most six dirty rows are copied (old/new rows of three alien ranks).
; Copy cost is about 7,000 CPU cycles including row setup; IRQs are held
; only during that copy, after the bottom dirty row, then restored.
; Vertical drops retain the original character-row snapping (8 pixels).
; The IRQ still owns sprites; the main loop owns these workspaces.
* = $4000 ; Place subsequent bytes at this address; this is an assembler origin.
alien_pixel_phase: !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
shifted_glyph_base: !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
shadow_mode: !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
dirty_rows: !fill 25,0 ; Emit the requested number of initial bytes for this array or data block.
publish_row: !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.
publish_bottom: !byte 0 ; Emit these byte values in order; table and bitmap layout depends on them.

; ----------------------------------------------------------------------
; ROUTINE prepare_alien_buffer
; WHAT: Copies 1024 live screen and colour bytes to $5000 and $5400.
; WHY: Starting from the live display preserves unrelated text and colours while the hidden image is edited.
; HOW: Sets shadow_mode=1 and clears 25 dirty flags.
; HOW: Changes A X flags. Includes screen-block tail in hidden copy only.
; ----------------------------------------------------------------------
prepare_alien_buffer: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #1 ; Put the literal 1 in A; # selects a value; N/Z reflect it.
    sta shadow_mode ; Write A to shadow mode; a store leaves the CPU flags unchanged.
    ldx #0 ; Put the literal 0 in X; # selects a value; N/Z reflect it.
buffer_copy: ; Name the address of the next emitted byte; a label emits no bytes.
    !for .p,0,3 { ; Repeat this emission at assembly time; it is not a CPU runtime loop.
        lda SCREEN+.p*256,x ; Read SCREEN+.p*256,x at the indexed element into A; update N/Z, preserve carry.
        sta $5000+.p*256,x ; Write A to $5000+.p*256,x; a store leaves the CPU flags unchanged.
        lda COLOR+.p*256,x ; Read COLOR+.p*256,x at the indexed element into A; update N/Z, preserve carry.
        sta $5400+.p*256,x ; Write A to $5400+.p*256,x; a store leaves the CPU flags unchanged.
    } ; Open/close the assembler block; braces are not CPU instructions.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    bne buffer_copy ; Branch to buffer_copy when Z=0 (nonzero/not equal); otherwise continue in sequence.
    ldx #24 ; Put the literal 24 in X; # selects a value; N/Z reflect it.
buffer_clean_flags: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #0 ; Put the literal 0 in A; # selects a value; N/Z reflect it.
    sta dirty_rows,x ; Write A to dirty rows,x; a store leaves the CPU flags unchanged.
    dex ; Decrease X by one modulo 256; set N/Z, preserve carry.
    bpl buffer_clean_flags ; Branch to buffer_clean_flags when N=0 (result bit 7 clear); otherwise continue in sequence.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; ----------------------------------------------------------------------
; ROUTINE mark_old_row_dirty
; WHAT: Input X indexes an old visible alien; derives row from cached displayed Y.
; WHY: An erased old position still needs publication even if no alien occupies that row afterwards.
; HOW: Marks dirty_rows entry. Preserves A and X; changes Y and flags.
; HOW: Caller must only use valid previously rendered alien state.
; ----------------------------------------------------------------------
mark_old_row_dirty: ; Name the address of the next emitted byte; a label emits no bytes.
; Preserve A=screen-pointer high, X=alien index, and the pointer.
    pha ; Push A on the hardware stack; balance this save with a later PLA.
    lda alien_draw_y,x ; Read alien draw y,x at the indexed element into A; update N/Z, preserve carry.
    sec ; Set carry before a new subtraction, meaning there is no incoming borrow.
    sbc #50 ; Subtract #50 and the incoming borrow from A; C=1 means no borrow.
    lsr ; Shift right with zero entering bit 7; old bit 0 goes to carry; update N/Z.
    lsr ; Shift right with zero entering bit 7; old bit 0 goes to carry; update N/Z.
    lsr ; Shift right with zero entering bit 7; old bit 0 goes to carry; update N/Z.
    tay ; Copy A to Y; N/Z reflect the copied byte.
    lda #1 ; Put the literal 1 in A; # selects a value; N/Z reflect it.
    sta dirty_rows,y ; Write A to dirty rows,y; a store leaves the CPU flags unchanged.
    pla ; Pull a byte into A; update N/Z but leave carry unchanged.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; ----------------------------------------------------------------------
; ROUTINE publish_alien_buffer
; WHAT: Input dirty_rows and prepared shadow display. Clears shadow_mode.
; WHY: Only changed rows need copying, and the copy must start after the affected display region.
; HOW: Waits below lowest dirty row; saves flags, masks IRQs, copies dirty rows.
; HOW: Restores saved flags. Changes A X Y pointers and self-modified read operands.
; ----------------------------------------------------------------------
publish_alien_buffer: ; Name the address of the next emitted byte; a label emits no bytes.
    lda #0 ; Put the literal 0 in A; # selects a value; N/Z reflect it.
    sta shadow_mode ; Write A to shadow mode; a store leaves the CPU flags unchanged.
; Find the bottom dirty row; no dirty rows means nothing to publish.
    ldx #24 ; Put the literal 24 in X; # selects a value; N/Z reflect it.
publish_find_bottom: ; Name the address of the next emitted byte; a label emits no bytes.
    lda dirty_rows,x ; Read dirty rows,x at the indexed element into A; update N/Z, preserve carry.
    bne publish_found_bottom ; Branch to publish_found_bottom when Z=0 (nonzero/not equal); otherwise continue in sequence.
    dex ; Decrease X by one modulo 256; set N/Z, preserve carry.
    bpl publish_find_bottom ; Branch to publish_find_bottom when N=0 (result bit 7 clear); otherwise continue in sequence.
    rts ; Pull the saved call address and add one; resume after the calling JSR.
publish_found_bottom: ; Name the address of the next emitted byte; a label emits no bytes.
    txa ; Copy X to A; N/Z reflect the copied byte.
    asl ; Shift left with zero entering bit 0; old bit 7 goes to carry; update N/Z.
    asl ; Shift left with zero entering bit 0; old bit 7 goes to carry; update N/Z.
    asl ; Shift left with zero entering bit 0; old bit 7 goes to carry; update N/Z.
    clc ; Clear carry before a new independent addition; do not break a byte-to-byte chain.
    adc #58 ; First raster line below this character row.
    sta publish_bottom ; Write A to publish bottom; a store leaves the CPU flags unchanged.
publish_wait: ; Name the address of the next emitted byte; a label emits no bytes.
; Wait for the NEXT occurrence, even if composition finished late.
; Test D011 bit 7 too: D012 repeats low values on PAL lines 256+.
    lda $d011 ; Read $d011 into A; update N/Z without changing carry.
    bmi publish_wait ; Branch to publish_wait when N=1 (result bit 7 set); otherwise continue in sequence.
    lda $d012 ; Read $d012 into A; update N/Z without changing carry.
    cmp publish_bottom ; Compare A with publish_bottom; set N/Z/C without changing A; C means >= unsigned.
    bne publish_wait ; Branch to publish_wait when Z=0 (nonzero/not equal); otherwise continue in sequence.
    php ; Preserve whether the caller had IRQs enabled (startup has not).
    sei ; Keep the bounded row copy free from KERNAL keyboard IRQ delays.
    lda #0 ; Put the literal 0 in A; # selects a value; N/Z reflect it.
    sta publish_row ; Write A to publish row; a store leaves the CPU flags unchanged.
publish_next_row: ; Name the address of the next emitted byte; a label emits no bytes.
    ldx publish_row ; Read publish row into X; update N/Z without changing carry.
    lda dirty_rows,x ; Read dirty rows,x at the indexed element into A; update N/Z, preserve carry.
    beq publish_skip_row ; Branch to publish_skip_row when Z=1 (zero/equal); otherwise continue in sequence.
    lda screen_row_lo,x ; Read screen row lo,x at the indexed element into A; update N/Z, preserve carry.
    sta ptr ; Write A to screen pointer low byte; a store leaves the CPU flags unchanged.
    sta color_ptr ; Write A to colour pointer low byte; a store leaves the CPU flags unchanged.
    lda screen_row_hi,x ; Read screen row hi,x at the indexed element into A; update N/Z, preserve carry.
    sta ptr+1 ; Write A to screen pointer high byte; a store leaves the CPU flags unchanged.
    clc ; Clear carry before a new independent addition; do not break a byte-to-byte chain.
    adc #$4c ; Add #$4c plus carry to A; C carries overflow into the next byte; set N/Z/V.
    sta publish_screen_read+2 ; Write A to publish screen read+2; a store leaves the CPU flags unchanged.
    clc ; Clear carry before a new independent addition; do not break a byte-to-byte chain.
    adc #4 ; Add #4 plus carry to A; C carries overflow into the next byte; set N/Z/V.
    sta publish_colour_read+2 ; Write A to publish colour read+2; a store leaves the CPU flags unchanged.
    lda screen_row_lo,x ; Read screen row lo,x at the indexed element into A; update N/Z, preserve carry.
    sta publish_screen_read+1 ; Write A to publish screen read+1; a store leaves the CPU flags unchanged.
    sta publish_colour_read+1 ; Write A to publish colour read+1; a store leaves the CPU flags unchanged.
    lda screen_row_hi,x ; Read screen row hi,x at the indexed element into A; update N/Z, preserve carry.
    clc ; Clear carry before a new independent addition; do not break a byte-to-byte chain.
    adc #$d4 ; Add #$d4 plus carry to A; C carries overflow into the next byte; set N/Z/V.
    sta color_ptr+1 ; Write A to colour pointer high byte; a store leaves the CPU flags unchanged.
    ldy #39 ; Put the literal 39 in Y; # selects a value; N/Z reflect it.
publish_cells: ; Name the address of the next emitted byte; a label emits no bytes.
publish_screen_read: ; Name the address of the next emitted byte; a label emits no bytes.
    lda $5000,y ; Operand is changed above to select this hidden row.
    sta (ptr),y ; Write A through the pointer plus index; CPU flags stay unchanged.
publish_colour_read: ; Name the address of the next emitted byte; a label emits no bytes.
    lda $5400,y ; Read $5400,y at the indexed element into A; update N/Z, preserve carry.
    sta (color_ptr),y ; Write A through the pointer plus index; CPU flags stay unchanged.
    dey ; Decrease Y by one modulo 256; set N/Z, preserve carry.
    bpl publish_cells ; Branch to publish_cells when N=0 (result bit 7 clear); otherwise continue in sequence.
publish_skip_row: ; Name the address of the next emitted byte; a label emits no bytes.
    inc publish_row ; Increase publish row by one modulo 256; set N/Z, preserve carry.
    lda publish_row ; Read publish row into A; update N/Z without changing carry.
    cmp #25 ; Compare A with #25; set N/Z/C without changing A; C means >= unsigned.
    bne publish_next_row ; Branch to publish_next_row when Z=0 (nonzero/not equal); otherwise continue in sequence.
    plp ; Restore the caller's IRQ state; a pending raster IRQ can now run.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; ----------------------------------------------------------------------
; ROUTINE install_shifted_glyphs
; WHAT: Copies 576 bytes from shifted_glyph_data to $3400..$363F.
; WHY: Precomputed horizontal phases turn fine pixel movement into inexpensive character-code stores.
; HOW: Three shapes times eight phases times three glyphs times eight rows.
; HOW: Changes A X flags. Character memory must be writable.
; ----------------------------------------------------------------------
install_shifted_glyphs: ; Name the address of the next emitted byte; a label emits no bytes.
; 576 bytes = 3 designs * 8 horizontal phases * 3 cells * 8 lines.
    ldx #0 ; Put the literal 0 in X; # selects a value; N/Z reflect it.
shift_copy_pages: ; Name the address of the next emitted byte; a label emits no bytes.
    lda shifted_glyph_data,x ; Read shifted glyph data,x at the indexed element into A; update N/Z, preserve carry.
    sta $3400,x ; Write A to $3400,x; a store leaves the CPU flags unchanged.
    lda shifted_glyph_data+256,x ; Read shifted glyph data+256,x at the indexed element into A; update N/Z, preserve carry.
    sta $3500,x ; Write A to $3500,x; a store leaves the CPU flags unchanged.
    inx ; Increase X by one modulo 256; set N/Z, preserve carry.
    bne shift_copy_pages ; Branch to shift_copy_pages when Z=0 (nonzero/not equal); otherwise continue in sequence.
    ldx #63 ; Put the literal 63 in X; # selects a value; N/Z reflect it.
shift_copy_tail: ; Name the address of the next emitted byte; a label emits no bytes.
    lda shifted_glyph_data+512,x ; Read shifted glyph data+512,x at the indexed element into A; update N/Z, preserve carry.
    sta $3600,x ; Write A to $3600,x; a store leaves the CPU flags unchanged.
    dex ; Decrease X by one modulo 256; set N/Z, preserve carry.
    bpl shift_copy_tail ; Branch to shift_copy_tail when N=0 (result bit 7 clear); otherwise continue in sequence.
    rts ; Pull the saved call address and add one; resume after the calling JSR.

; ACME computes these patterns at assembly time: no shift work per frame.
; Original design bytes are preserved above for beginners to compare.
shifted_glyph_data: ; Name the address of the next emitted byte; a label emits no bytes.
; alien_glyph_left: horizontal pixel offset 0
    !byte $00,$07,$1f,$3f,$77,$7f,$2a,$44 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$e0,$f8,$fc,$ee,$fe,$54,$22 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$00,$00,$00,$00,$00,$00,$00 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_glyph_left: horizontal pixel offset 1
    !byte $00,$03,$0f,$1f,$3b,$3f,$15,$22 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$f0,$fc,$fe,$f7,$ff,$2a,$11 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$00,$00,$00,$00,$00,$00,$00 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_glyph_left: horizontal pixel offset 2
    !byte $00,$01,$07,$0f,$1d,$1f,$0a,$11 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$f8,$fe,$ff,$fb,$ff,$95,$08 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$00,$00,$00,$80,$80,$00,$80 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_glyph_left: horizontal pixel offset 3
    !byte $00,$00,$03,$07,$0e,$0f,$05,$08 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$fc,$ff,$ff,$fd,$ff,$4a,$84 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$00,$00,$80,$c0,$c0,$80,$40 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_glyph_left: horizontal pixel offset 4
    !byte $00,$00,$01,$03,$07,$07,$02,$04 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$7e,$ff,$ff,$7e,$ff,$a5,$42 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$00,$80,$c0,$e0,$e0,$40,$20 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_glyph_left: horizontal pixel offset 5
    !byte $00,$00,$00,$01,$03,$03,$01,$02 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$3f,$ff,$ff,$bf,$ff,$52,$21 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$00,$c0,$e0,$70,$f0,$a0,$10 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_glyph_left: horizontal pixel offset 6
    !byte $00,$00,$00,$00,$01,$01,$00,$01 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$1f,$7f,$ff,$df,$ff,$a9,$10 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$80,$e0,$f0,$b8,$f8,$50,$88 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_glyph_left: horizontal pixel offset 7
    !byte $00,$00,$00,$00,$00,$00,$00,$00 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$0f,$3f,$7f,$ef,$ff,$54,$88 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$c0,$f0,$f8,$dc,$fc,$a8,$44 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_crab_left: horizontal pixel offset 0
    !byte $00,$42,$24,$7f,$db,$ff,$a5,$24 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$42,$24,$fe,$db,$ff,$a5,$24 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$00,$00,$00,$00,$00,$00,$00 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_crab_left: horizontal pixel offset 1
    !byte $00,$21,$12,$3f,$6d,$7f,$52,$12 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$21,$12,$ff,$ed,$ff,$d2,$12 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$00,$00,$00,$80,$80,$80,$00 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_crab_left: horizontal pixel offset 2
    !byte $00,$10,$09,$1f,$36,$3f,$29,$09 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$90,$09,$ff,$f6,$ff,$69,$09 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$80,$00,$80,$c0,$c0,$40,$00 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_crab_left: horizontal pixel offset 3
    !byte $00,$08,$04,$0f,$1b,$1f,$14,$04 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$48,$84,$ff,$7b,$ff,$b4,$84 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$40,$80,$c0,$60,$e0,$a0,$80 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_crab_left: horizontal pixel offset 4
    !byte $00,$04,$02,$07,$0d,$0f,$0a,$02 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$24,$42,$ff,$bd,$ff,$5a,$42 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$20,$40,$e0,$b0,$f0,$50,$40 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_crab_left: horizontal pixel offset 5
    !byte $00,$02,$01,$03,$06,$07,$05,$01 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$12,$21,$ff,$de,$ff,$2d,$21 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$10,$20,$f0,$d8,$f8,$28,$20 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_crab_left: horizontal pixel offset 6
    !byte $00,$01,$00,$01,$03,$03,$02,$00 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$09,$90,$ff,$6f,$ff,$96,$90 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$08,$90,$f8,$6c,$fc,$94,$90 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_crab_left: horizontal pixel offset 7
    !byte $00,$00,$00,$00,$01,$01,$01,$00 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$84,$48,$ff,$b7,$ff,$4b,$48 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$84,$48,$fc,$b6,$fe,$4a,$48 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_octopus_left: horizontal pixel offset 0
    !byte $00,$1f,$3f,$6f,$ff,$ff,$36,$63 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$f8,$fc,$f6,$ff,$ff,$6c,$c6 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$00,$00,$00,$00,$00,$00,$00 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_octopus_left: horizontal pixel offset 1
    !byte $00,$0f,$1f,$37,$7f,$7f,$1b,$31 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$fc,$fe,$fb,$ff,$ff,$36,$e3 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$00,$00,$00,$80,$80,$00,$00 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_octopus_left: horizontal pixel offset 2
    !byte $00,$07,$0f,$1b,$3f,$3f,$0d,$18 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$fe,$ff,$fd,$ff,$ff,$9b,$f1 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$00,$00,$80,$c0,$c0,$00,$80 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_octopus_left: horizontal pixel offset 3
    !byte $00,$03,$07,$0d,$1f,$1f,$06,$0c ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$ff,$ff,$fe,$ff,$ff,$cd,$78 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$00,$80,$c0,$e0,$e0,$80,$c0 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_octopus_left: horizontal pixel offset 4
    !byte $00,$01,$03,$06,$0f,$0f,$03,$06 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$ff,$ff,$ff,$ff,$ff,$66,$3c ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$80,$c0,$60,$f0,$f0,$c0,$60 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_octopus_left: horizontal pixel offset 5
    !byte $00,$00,$01,$03,$07,$07,$01,$03 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$ff,$ff,$7f,$ff,$ff,$b3,$1e ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$c0,$e0,$b0,$f8,$f8,$60,$30 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_octopus_left: horizontal pixel offset 6
    !byte $00,$00,$00,$01,$03,$03,$00,$01 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$7f,$ff,$bf,$ff,$ff,$d9,$8f ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$e0,$f0,$d8,$fc,$fc,$b0,$18 ; Emit these byte values in order; table and bitmap layout depends on them.
; alien_octopus_left: horizontal pixel offset 7
    !byte $00,$00,$00,$00,$01,$01,$00,$00 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$3f,$7f,$df,$ff,$ff,$6c,$c7 ; Emit these byte values in order; table and bitmap layout depends on them.
    !byte $00,$f0,$f8,$ec,$fe,$fe,$d8,$8c ; Emit these byte values in order; table and bitmap layout depends on them.

!if * > $5000 { !error "Rendering code overlaps hidden screen" } ; Check this assembly-time condition; reject an overlapping memory layout.

;;; ============================================================
;;; CHIP-8 Interpreter
;;; ============================================================

.feature line_continuations +

        .setcpu "6502"

        .include "apple2.inc"
        .include "opcodes.inc"
        .include "prodos.inc"

        .org    $2000

;;; TODO:
;;; * [ ] Include a "STARTUP" equivalent default name
;;; * [ ] Allow configurable border/background/foreground colors
;;; * [ ] Have key to cycle colors (or whole palettes)
;;; * [ ] Consider having bitmap distinct from display
;;; * [ ] Test on Mac IIe Card

;;; ============================================================

;;; Build options for various CHIP-8 ambiguities

;;; Should `8XY1`, `8XY2` and `8XY3` reset `VF`?
;;; https://tobiasvl.github.io/blog/write-a-chip-8-emulator/#logical-and-arithmetic-instructions
QUIRKS_VF_RESET = 1

;;; Should `FX55` and `FX65` increment `I`?
;;; https://tobiasvl.github.io/blog/write-a-chip-8-emulator/#fx55-and-fx65-store-and-load-memory
QUIRKS_MEMORY   = 1

;;; Should `VF` be set to 1 if `FX1E` causes overflow?
;;; https://tobiasvl.github.io/blog/write-a-chip-8-emulator/#fx1e-add-to-index
QUIRKS_OVERFLOW = 1

;;; Should sprite drawing be clamped to 60Hz?
;;; https://github.com/Timendus/chip8-test-suite?tab=readme-ov-file#the-test
QUIRKS_DISP_VBL = 1

;;; Should sprites clip or wrap?
;;; https://github.com/Timendus/chip8-test-suite?tab=readme-ov-file#the-test
QUIRKS_CLIPPING = 1

;;; ============================================================

;;; Equates
SPKR            := $C030
CLR80VID        := $C00C
SET80VID        := $C00D
CLR80STORE      := $C000        ; in CC65 as `CLR80COL` (confusing!)
SET80STORE      := $C001        ; in CC65 as `SET80COL` (confusing!)

INIT            := $FB2F
VERSION         := $FBB3        ; Monitor ROM ID byte. $06 = IIe or later
ZIDBYTE         := $FBC0        ; * $EA = IIe, $E0 = IIe enh/IIgs, $00 = IIc/IIc+
BELL1           := $FBDD
HOME            := $FC58
CROUT           := $FD8E
COUT            := $FDED
PRBYTE          := $FDDA
IDROUTINE       := $FE1F        ; RTS ($60) on pre-IIgs, clears carry on IIgs
SETVID          := $FE93
SETNORM         := $FE84
SETKBD          := $FE89

;;; ============================================================
;;; Memory map

;;;              Main           Aux
;;;          :             : :             :
;;;          |             | |             |
;;;          |             | | (unused)    |
;;;  $5300   +-------------+ |             |
;;;          | Bitmap      | |             |
;;;  $5200   +-------------+ |             |
;;;          | CHIP-8      | |             |
;;;          | Stack       | |             |
;;;  $5000   +-------------+ |             |
;;;          |             | |             |
;;;          |             | |             |
;;;          | CHIP-8      | |             |
;;;          | Memory      | |             |
;;;  $4000   +-------------+ |             |
;;;          |             | |             |
;;;          |             | |             |
;;;          |             | |             |
;;;          | Interpreter | |             |
;;;  $2000   +-------------+ |             |
;;;          |             | |             |
;;;          |             | |             |
;;;          |             | |             |
;;;          | I/O         | |             |
;;;   $800   +-------------+ +-------------+
;;;          | Double      | | Double      |
;;;          | Low-Res     | | Low-Res     |
;;;          | Graphics    | | Graphics    |
;;;   $400   +-------------+ +-------------+
;;;          | (unused)    | |             |
;;;   $300   +-------------+ +-------------+
;;;          | (unused)    | |             |
;;;   $200   +-------------+ +-------------+
;;;          | Stack       | |             |
;;;   $100   +-------------+ +-------------+
;;;          | Zero Page   | |             |
;;;    $00   +-------------+ +-------------+
;;;

IO_BUF       := $800            ; $800...$BFF

CHIP8_MEMORY := $4000           ; virtual memory address
CHIP8_SIZE   := $1000           ; 4K

CHIP8_STACK_LO := $5000         ; low bytes of stack entries
CHIP8_STACK_HI := $5100         ; high bytes of stack entries

CHIP8_BITMAP   := $5200         ; copy of screen bitmap (1 bit per pixel)

ADDR_MASK_HI    := %00001111    ; mask high address byte to 12 bits
.assert .lobyte(CHIP8_MEMORY) = 0, error, "code assumes page alignment"

LOAD_ADDR       := $200
FONT_ADDR       := $050

;;; ============================================================
;;; Graphics

COLOR_BORDER = 2                ; dark blue
COLOR_BG     = 0                ; black
COLOR_FG     = 15               ; white

CHIP8_SCREEN_WIDTH  = 64
CHIP8_SCREEN_HEIGHT = 32

;;; ============================================================
;;; Start of Binary
;;; ============================================================

;;; ============================================================
;;; Interpreter protocol
;;; http://www.easy68k.com/paulrsm/6502/PDOS8TRM.HTM#5.1.5.1

        jmp     start
        .byte   $EE, $EE        ; signature
        .byte   65              ; pathname buffer length ($2005)
str_path:
        .res    65, 0

;;; ============================================================
;;; ProDOS parameters

.proc open_params
param_count:    .byte   3
pathname:       .addr   str_path
io_buffer:      .addr   IO_BUF
ref_num:        .byte   0
.endproc

.proc read_params
param_count:    .byte   4
ref_num:        .byte   0
data_buffer:    .addr   CHIP8_MEMORY + LOAD_ADDR
request_count:  .word   CHIP8_SIZE - LOAD_ADDR
trans_count:    .word   0
.endproc

.proc close_params
param_count:    .byte   1
ref_num:        .addr   0
.endproc

.proc quit_params
param_count:    .byte   4
quit_type:      .byte   0
reserved1:      .word   0
reserved2:      .byte   0
reserved3:      .word   0
.endproc

;;; ============================================================

start:
        lda     #$95            ; Disable 80-col firmware
        jsr     COUT
        jsr     SetTextMode

        ;; ----------------------------------------
        ;; Can we run on this model? (requires DGR)

        lda     VERSION         ; IIe or later = $06
        cmp     #$06
        bne     quit            ; no, just exit

        lda     MACHID
        and     #%00110000      ; 128K?
        cmp     #%00110000
        bne     quit            ; no, just exit

        ;; ----------------------------------------
        ;; Pathname passed?

        lda     str_path
        bne     load_file

quit:
        ;; Quit back to ProDOS
        jsr     SetTextMode

        MLI_CALL QUIT, quit_params
        brk

        ;; ----------------------------------------
        ;; Error encountered - just beep annoyingly
fail:
        jsr     BELL1
        jmp     quit

        ;; ----------------------------------------
        ;; Load the file

load_file:
        jsr     InitMemory
        jsr     InitRand


        MLI_CALL OPEN, open_params
        bcs     fail
        lda     open_params::ref_num
        sta     read_params::ref_num
        sta     close_params::ref_num

        MLI_CALL READ, read_params
        bcs     fail

        MLI_CALL CLOSE, close_params
        bcs     fail

;;; ============================================================
;;; Zero Page Usage
;;; ============================================================

.struct
.org $00

pc_ptr          .addr           ; pointer to current instruction
instr           .word           ; copy of current instruction
stack_ptr       .byte           ; offset into stack
vbl             .byte           ; VBL state (bit7 = blanking)

;;; Timers
delay_timer     .byte
sound_timer     .byte

;;; Registers
addr_ptr        .addr           ; `I` (address register)
registers       .byte 16        ; `V0`...`VF`
addr_copy       .addr           ; temporary copy of `I`

;;; Keys
keys            .byte 16        ; state of keys 0-F (bit7 = 1 if pressed)
akd             .byte           ; do we think any key is down

;;; Graphics
graph_ptr       .addr           ; pointer for graphics work
fg_color        .byte           ; currently constant but dynamic in future
bg_color        .byte           ; "
fg_bits_main    .byte           ; pre-computed/shifted color bits pattern
fg_bits_aux     .byte           ; "
bg_bits_main    .byte           ; "
bg_bits_aux     .byte           ; "

fg              .byte           ; temp during drawing
bg              .byte           ; "
mask1           .byte           ; bits we're setting
mask2           .byte           ; bits we're keeping

sprite_x        .byte
sprite_y        .byte
sprite_rows     .byte
collision       .byte

_ZP_END_        .byte
.endstruct

;;; NOTES: Avoid $40-$4E (used by ProDOS)
.assert _ZP_END_ <= $40, error, "ZP collision"

;;; NOTE: `pc_ptr` and `addr_ptr` are stored as real memory addresses,
;;; not virtual memory addresses.

        ;; ----------------------------------------
        ;; Set up display

        ;; IIc? Enable VBL
        lda     ZIDBYTE         ; IIc = $00
        bne     :+
        lda     #0              ; don't invert like we do on the IIe
        sta     VBL_XOR
        sei                     ; we'll just poll
        sta     IOUDISOFF
        bit     ENVBL
        bit     PTRIG           ; reset `RDVBL`
:
        ;; IIgs? Invert VBL sense
        sec
        jsr     IDROUTINE       ; clears carry on IIgs
        bcs     :+
        lda     #0              ; don't invert like we do on the IIe
        sta     VBL_XOR
:
        ;; Macintosh IIe Option Card? No palette swap
        lda     BELL1
        cmp     #$02            ; illegal opcode $02 is signature
        bne     :+
        lda     #OPC_RTS
        sta     ROR8            ; nerf the routine
:
        lda     #COLOR_BG
        sta     bg_color
        lda     #COLOR_FG
        sta     fg_color
        jsr     ExpandColorPatterns

        sta     LORES
        sta     MIXCLR
        sta     TXTCLR
        sta     SET80VID
        sta     DHIRESON

;;; ============================================================
;;; Interpreter

        ;; Initialize all registers
        lda     #0
        sta     stack_ptr
        sta     delay_timer
        sta     sound_timer
        sta     addr_ptr
        sta     addr_ptr+1
        ldx     #$F
:       sta     registers,x
        dex
        bpl     :-

        lda     #<(CHIP8_MEMORY+LOAD_ADDR)
        sta     pc_ptr
        lda     #>(CHIP8_MEMORY+LOAD_ADDR)
        sta     pc_ptr+1

        sta     KBDSTRB

        lda     border_color
        jsr     DrawBorder      ; calls `WaitVBL`, so ensure timers are reset

        jsr     ClearKeys
        jsr     ClearScreen     ; calls `WaitVBL`, so ensure timers are reset

        ;; fall through to fetch/execute/decode

;;; ============================================================
;;; Fetch / Decode / Execute

InterpreterLoop:

        ;; --------------------------------------------------
        ;; Key state

        jsr     UpdateKeys

        ;; --------------------------------------------------
        ;; Service timers

        jsr     ServiceTimers

        ;; --------------------------------------------------
        ;; Fetch

        ldy     #0
        lda     (pc_ptr),y
        sta     instr+1         ; big-endian
        iny
        lda     (pc_ptr),y
        sta     instr

        jsr     IncPCPtrBy2

        ;; --------------------------------------------------
        ;; Decode

        ;; Use the high nibble to index a jump table, since most
        ;; CHIP-8 instructions are determined solely by the high
        ;; nibble.

        lda     instr+1
        lsr
        lsr
        lsr
        lsr
        tax
        lda     dispatch_lo,x
        sta     dispatch
        lda     dispatch_hi,x
        sta     dispatch+1

        ;; Not every instruction is of the form _XY_ but most are so
        ;; load nibbles into X and Y

        lda     instr
        and     #%11110000
        lsr
        lsr
        lsr
        lsr
        tay                     ; Y = Y

        lda     instr+1
        and     #%00001111
        tax                     ; X = X

        ;; And using __NN is common so load low byte into A

        lda     instr           ; commonly needed

        ;; --------------------------------------------------
        ;; Execute

        dispatch := *+1
        jsr     $1234           ; self-modified

        jmp     InterpreterLoop

dispatch_lo:
        .lobytes        Op0, Op1, Op2, Op3
        .lobytes        Op4, Op5, Op6, Op7
        .lobytes        Op8, Op9, OpA, OpB
        .lobytes        OpC, OpD, OpE, OpF
dispatch_hi:
        .hibytes        Op0, Op1, Op2, Op3
        .hibytes        Op4, Op5, Op6, Op7
        .hibytes        Op8, Op9, OpA, OpB
        .hibytes        OpC, OpD, OpE, OpF


;;; ============================================================

;;; All of the following are called with:
;;; X register = X (assuming _X__)
;;; Y register = Y (assuming __Y_)
;;; A register = low byte (i.e. __NN)

;;; ============================================================

.proc Op0
        cpx     #0
        bne     fail
        ;;; `0NNN` - Execute machine language subroutine (not supported)

        cmp     #$EE
        bne     :+
        ;; `00EE` - Return from subroutine
        ldx     stack_ptr
        dex
        lda     CHIP8_STACK_LO,x
        sta     pc_ptr
        lda     CHIP8_STACK_HI,x
        sta     pc_ptr+1
        stx     stack_ptr
        rts
:
        cmp     #$E0
        bne     fail
        ;; `00E0` - Clear the screen
        jmp     ClearScreen

fail:   jmp     BadInstruction
.endproc

;;; ============================================================

.proc Op1
        ;; `1NNN` - Jump to address `NNN`
        sta     pc_ptr
        txa
        and     #ADDR_MASK_HI
        ora     #.hibyte(CHIP8_MEMORY)
        sta     pc_ptr+1
        rts
.endproc
;;; ============================================================

.proc Op2
        ;; `2NNN` - Execute subroutine starting at address `NNN`
        pha
        txa
        pha

        ldx     stack_ptr
        lda     pc_ptr
        sta     CHIP8_STACK_LO,x
        lda     pc_ptr+1
        sta     CHIP8_STACK_HI,x
        inx
        stx     stack_ptr

        pla
        tax
        pla
        ;; now same as jump
        jmp     Op1
.endproc

;;; ============================================================

.proc Op3
        ;; `3XNN` - Skip the following instruction if the value of
        ;; register `VX` equals `NN`
        cmp     registers,x     ; A = VX
        bne     :+
        jsr     IncPCPtrBy2
:       rts
.endproc

;;; ============================================================

.proc Op4
        ;; `4XNN` - Skip the following instruction if the value of
        ;; register `VX` is not equal to `NN`
        cmp     registers,x     ; A = VX
        beq     :+
        jsr     IncPCPtrBy2
:       rts
.endproc

;;; ============================================================

.proc Op5
        ;; `5XY0` - Skip the following instruction if the value of
        ;; register `VX` is equal to the value of register `VY`
        and     #%00001111
        bne     fail

        lda     registers,x
        cmp     registers,y
        bne     :+
        jsr     IncPCPtrBy2
:       rts

fail:   jmp     BadInstruction
.endproc

;;; ============================================================

.proc Op6
        ;; `6XNN` - Store number `NN` in register `VX`
        sta     registers,x
        rts
.endproc

;;; ============================================================

.proc Op7
        ;; `7XNN` - Add the value `NN` to register `VX`
        clc
        adc     registers,x
        sta     registers,x
        rts
.endproc

;;; ============================================================

.proc Op8
        ;; Secondary decode / dispatch
        txa
        pha
        lda     instr
        and     #%00001111
        tax
        lda     dispatch_lo,x
        sta     dispatch
        lda     dispatch_hi,x
        sta     dispatch+1
        pla
        tax

        dispatch := *+1
        jmp     $1234           ; self-modified

dispatch_lo:
        .lobytes        Op8xy0, Op8xy1, Op8xy2, Op8xy3
        .lobytes        Op8xy4, Op8xy5, Op8xy6, Op8xy7
        .lobytes        Op8xy8, Op8xy9, Op8xyA, Op8xyB
        .lobytes        Op8xyC, Op8xyD, Op8xyE, Op8xyF
dispatch_hi:
        .hibytes        Op8xy0, Op8xy1, Op8xy2, Op8xy3
        .hibytes        Op8xy4, Op8xy5, Op8xy6, Op8xy7
        .hibytes        Op8xy8, Op8xy9, Op8xyA, Op8xyB
        .hibytes        Op8xyC, Op8xyD, Op8xyE, Op8xyF
.endproc

;;; --------------------------------------------------

.proc Op8xy0
        ;; `8XY0` - Store the value of register `VY` in register `VX`
        lda     registers,y
        sta     registers,x
        rts
.endproc

;;; --------------------------------------------------

.proc Op8xy1
        ;; `8XY1` - Set `VX` to `VX` OR `VY`
        lda     registers,x
        ora     registers,y
        sta     registers,x
.if ::QUIRKS_VF_RESET
        lda     #0
        sta     registers+$F
.endif
        rts
.endproc

;;; --------------------------------------------------

.proc Op8xy2
        ;; `8XY2` - Set `VX` to `VX` AND `VY`
        lda     registers,x
        and     registers,y
        sta     registers,x
.if ::QUIRKS_VF_RESET
        lda     #0
        sta     registers+$F
.endif
        rts
.endproc

;;; --------------------------------------------------

.proc Op8xy3
        ;; `8XY3` - Set `VX` to `VX` XOR `VY`
        lda     registers,x
        eor     registers,y
        sta     registers,x
.if ::QUIRKS_VF_RESET
        lda     #0
        sta     registers+$F
.endif
        rts
.endproc

;;; --------------------------------------------------=

.proc Op8xy4
        ;; `8XY4` - Add the value of register `VY` to register `VX`
        ;; ; Set `VF` to 01 if a carry occurs
        ;; ; Set `VF` to 00 if a carry does not occur
        lda     registers,x
        clc
        adc     registers,y
        sta     registers,x
        jmp     set_vf_to_carry
.endproc

;;; --------------------------------------------------

.proc Op8xy5
        ;; `8XY5` - Subtract the value of register `VY` from register
        ;; `VX` ; Set `VF` to 00 if a borrow occurs ; Set `VF` to 01
        ;; if a borrow does not occur
        lda     registers,x
        sec
        sbc     registers,y
        sta     registers,x
        jmp     set_vf_to_carry
.endproc

;;; --------------------------------------------------

.proc Op8xy6
        ;; `8XY6` - Store the value of register `VY` shifted right one
        ;; bit in register `VX` ; Set register `VF` to the least
        ;; significant bit prior to the shift ; `VY` is unchanged
        lda     registers,y
        lsr
        sta     registers,x
        jmp     set_vf_to_carry
.endproc

;;; --------------------------------------------------

.proc Op8xy7
        ;; `8XY7` - Set register `VX` to the value of `VY` minus `VX`
        ;; ; Set `VF` to 00 if a borrow occurs ; Set `VF` to 01 if a
        ;; borrow does not occur
        lda     registers,y
        sec
        sbc     registers,x
        sta     registers,x
        jmp     set_vf_to_carry
.endproc

;;; --------------------------------------------------

Op8xy8 := BadInstruction
Op8xy9 := BadInstruction
Op8xyA := BadInstruction
Op8xyB := BadInstruction
Op8xyC := BadInstruction
Op8xyD := BadInstruction

;;; --------------------------------------------------

.proc Op8xyE
        ;; `8XYE` - Store the value of register `VY` shifted left one
        ;; bit in register `VX` ; Set register `VF` to the most
        ;; significant bit prior to the shift ; `VY` is unchanged
        lda     registers,y
        asl
        sta     registers,x
        .assert * = set_vf_to_carry, error, "fall-through"
.endproc

set_vf_to_carry:
        rol
        and     #1
        sta     registers+$F
        rts

;;; --------------------------------------------------

Op8xyF := BadInstruction

;;; ============================================================

.proc Op9
        ;; `9XY0` - Skip the following instruction if the value of
        ;; register `VX` is not equal to the value of register `VY`
        and     #%00001111
        bne     fail

        lda     registers,x
        cmp     registers,y
        beq     :+
        jsr     IncPCPtrBy2
:       rts

fail:   jmp     BadInstruction
.endproc

;;; ============================================================

.proc OpA
        ;; `ANNN` - Store memory address `NNN` in register `I`
        sta     addr_ptr
        txa
        and     #ADDR_MASK_HI
        ora     #.hibyte(CHIP8_MEMORY)
        sta     addr_ptr+1
        rts
.endproc

;;; ============================================================

.proc OpB
        ;; `BNNN` - Jump to address `NNN` + `V0`
        clc
        adc     registers+$0
        sta     pc_ptr
        txa
        adc     #0
        and     #ADDR_MASK_HI
        ora     #.hibyte(CHIP8_MEMORY)
        sta     pc_ptr+1
        rts
.endproc

;;; ============================================================

.proc OpC
        ;; `CXNN` - Set `VX` to a random number with a mask of `NN`
        jsr     Random
        and     instr
        sta     registers,x

        rts
.endproc

;;; ============================================================

.proc OpD
        ;; `DXYN` - Draw a sprite at position `VX`, `VY` with `N`
        ;; bytes of sprite data starting at the address stored in `I`;
        ;; Set `VF` to 01 if any set pixels are changed to unset, and
        ;; 00 otherwise
        lda     registers,x
        and     #CHIP8_SCREEN_WIDTH-1 ; coordinates wrap
        tax
        lda     registers,y
        and     #CHIP8_SCREEN_HEIGHT-1 ; coordinates wrap
        tay
        lda     instr
        and     #%00001111
        jsr     DrawSprite
        rol
        and     #1
        sta     registers+$F
        rts
.endproc

;;; ============================================================

.proc OpE
        lda     registers,x
        and     #%00001111      ; TODO: Invalid key behavior?
        tax                     ; X = key

        lda     instr
        cmp     #$9E
        bne     :+
        ;; `EX9E` - Skip the following instruction if the key
        ;; corresponding to the hex value currently stored in register
        ;; `VX` is pressed
        lda     keys,x
        bpl     ret             ; N set if pressed
        jmp     IncPCPtrBy2
:
        cmp     #$A1
        bne     :+
        ;; `EXA1` - Skip the following instruction if the key
        ;; corresponding to the hex value currently stored in register
        ;; `VX` is not pressed
        lda     keys,x
        bmi     ret             ; N clear if not pressed
        jmp     IncPCPtrBy2
:
        jmp     BadInstruction

ret:    rts
.endproc

;;; ============================================================

.proc OpF
        cmp     #$07
        bne     :+
        ;; `FX07` - Store the current value of the delay timer in
        ;; register `VX`
        lda     delay_timer
        sta     registers,x
        rts
:
        cmp     #$0A
        bne     :+
        ;; `FX0A` - Wait for a keypress and store the result in
        ;; register `VX`
        txa
        pha
        jsr     WaitForKey
        tay
        pla
        tax
        sty     registers,x
        rts
:
        cmp     #$15
        beq     OpFX15

        cmp     #$18
        beq     OpFX18

        cmp     #$1E
        beq     OpFX1E

        cmp     #$29
        beq     OpFX29

        cmp     #$33
        beq     OpFX33

        cmp     #$55
        beq     OpFX55

        cmp     #$65
        beq     OpFX65

        jmp     BadInstruction
.endproc

.proc OpFX15
        ;; `FX15` - Set the delay timer to the value of register `VX`
        lda     registers,x
        sta     delay_timer
        rts
.endproc

.proc OpFX18
        ;; `FX18` - Set the sound timer to the value of register `VX`
        lda     registers,x
        sta     sound_timer
        rts
.endproc

.proc OpFX1E
        ;; `FX1E` - Add the value stored in register `VX` to register
        ;; `I`
        lda     registers,x
        clc
        adc     addr_ptr
        sta     addr_ptr
        lda     #0
        adc     addr_ptr+1
        and     #ADDR_MASK_HI
        ora     #.hibyte(CHIP8_MEMORY)
        sta     addr_ptr+1
.if ::QUIRKS_OVERFLOW
        rol
        and     #1
        sta     registers+$F
.endif
        rts
.endproc

.proc OpFX29
        ;; `FX29` - Set `I` to the memory address of the sprite data
        ;; corresponding to the hexadecimal digit stored in register
        ;; `VX`
        lda     registers,x
        and     #%00001111      ; only use low nibble
        tax
        lda     times_5_table,x
        clc
        adc     #.lobyte(CHIP8_MEMORY + FONT_ADDR)
        sta     addr_ptr
        lda     #0
        adc     #.hibyte(CHIP8_MEMORY + FONT_ADDR)
        sta     addr_ptr+1
        rts
.endproc

.proc OpFX33
        ;; `FX33` - Store the binary-coded decimal equivalent of the
        ;; value stored in register `VX` at addresses `I`, `I` + 1,
        ;; and `I` + 2
        jsr     SaveAddrPtr

        ldy     #0
        lda     registers,x

        ;; Hundreds
        ldx     #$100-1
:       inx
        sbc     #100
        bcs     :-
        adc     #100
        pha
        txa
        sta     (addr_ptr),y
        jsr     IncAddrPtr
        pla

        ;; tens
        ldx     #$100-1
:       inx
        sbc     #10
        bcs     :-
        adc     #10
        pha
        txa
        sta     (addr_ptr),y
        jsr     IncAddrPtr
        pla

        ;; ones
        sta     (addr_ptr),y

        jmp     RestoreAddrPtr
.endproc

.proc OpFX55
        ;; `FX55` - Store the values of registers `V0` to `VX`
        ;; inclusive in memory starting at address `I`; `I` is set to
        ;; `I` + `X` + 1 after operation²

.if !::QUIRKS_MEMORY
        jsr     SaveAddrPtr
.endif
        inx
        stx     limit
        ldx     #0
        ldy     #0
:       lda     registers,x
        sta     (addr_ptr),y
        jsr     IncAddrPtr
        inx
        limit := *+1
        cpx     #$12            ; self-modified
        bcc     :-
.if !::QUIRKS_MEMORY
        jsr     RestoreAddrPtr
.endif
        rts
.endproc

.proc OpFX65
        ;; `FX65` - Fill registers `V0` to `VX` inclusive with the
        ;; values stored in memory starting at address `I` ; `I` is
        ;; set to `I` + `X` + 1 after operation²

.if !::QUIRKS_MEMORY
        jsr     SaveAddrPtr
.endif
        inx
        stx     limit
        ldx     #0
        ldy     #0
:       lda     (addr_ptr),y
        sta     registers,x
        jsr     IncAddrPtr
        inx
        limit := *+1
        cpx     #$12            ; self-modified
        bcc     :-
.if !::QUIRKS_MEMORY
        jsr     RestoreAddrPtr
.endif
        rts
.endproc

;;; ============================================================
;;; Advance instruction pointer to the next word
;;; Wraps to keep within virtual memory block.

.proc IncPCPtrBy2
        lda     pc_ptr
        clc
        adc     #2
        sta     pc_ptr

        lda     pc_ptr+1
        adc     #0
        and     #ADDR_MASK_HI
        ora     #.hibyte(CHIP8_MEMORY)
        sta     pc_ptr+1

        rts
.endproc

;;; ============================================================
;;; Advance address pointer (`I` register) to next byte.
;;; Wraps to keep within virtual memory block.

.proc IncAddrPtr
        inc     addr_ptr
        bne     :+

        inc     addr_ptr+1
        lda     addr_ptr+1
        and     #ADDR_MASK_HI
        ora     #.hibyte(CHIP8_MEMORY)
        sta     addr_ptr+1
:
        rts
.endproc

;;; Save a copy of the address pointer (`I` register) for
;;; operations that temporarily mutate it.

.proc SaveAddrPtr
        lda     addr_ptr
        sta     addr_copy
        lda     addr_ptr+1
        sta     addr_copy+1
        rts
.endproc

.proc RestoreAddrPtr
        lda     addr_copy
        sta     addr_ptr
        lda     addr_copy+1
        sta     addr_ptr+1
        rts
.endproc

;;; ============================================================
;;; Update timers and `vbl`, generate sound. This is like a faux
;;; interrupt handler. Must be called regularly e.g. any wait or
;;; potentially slow loop.

;;; Preserves A,X,Y
.proc ServiceTimers
        ;; --------------------------------------------------
        ;; Preserve registers

        pha
        txa
        pha
        tya
        pha

        ;; --------------------------------------------------
        ;; Use VBL to update timers

        lda     RDVBLBAR        ; on IIc/IIgs is actually `RDVBL`, i.e. high is blanking
        vbl_xor := *+1          ; flip it on the IIe to match (makes more sense)
        eor     #$80            ; self-modified; flip it on IIe
        tax
        eor     vbl
        bpl     done_vbl        ; no change
        txa
        sta     vbl             ; record new state

        ;; We care about the transition from drawing to blanking (0->1)
        bpl     done_vbl

        ;; IIc: Need to reset `RDVBL` once it has gone high
        lda     ZIDBYTE
        bne     :+              ; IIc = $00
        sta     PTRIG
:
        ;; Decrement 60Hz timers
        lda     sound_timer
        beq     :+              ; decrement if not zero
        dec     sound_timer
:
        lda     delay_timer
        beq     :+              ; decrement if not zero
        dec     delay_timer
:

done_vbl:

        ;; --------------------------------------------------
        ;; Make sound?

        lda     sound_timer
        cmp     #2
        bcc     :+
        sta     SPKR
:
        ;; --------------------------------------------------
        ;; Restore registers

        pla
        tay
        pla
        tax
        pla

        rts
.endproc
VBL_XOR := ServiceTimers::vbl_xor

;;; ============================================================

.proc WaitVBL
:       jsr     ServiceTimers
        lda     vbl             ; wait to exit VBL
        bmi     :-
:       jsr     ServiceTimers   ; wait for next VBL
        lda     vbl
        bpl     :-
        rts
.endproc

;;; ============================================================
;;; Initialization

.proc InitMemory

        ;; Zero CHIP-8 memory
        lda     #$00
        ldy     #.hibyte(CHIP8_SIZE) ; number of pages
ploop:  ldx     #$00                 ; clear a whole page
        addr := *+1
bloop:  sta     CHIP8_MEMORY,x  ; self-modified
        dex
        bne     bloop
        inc     addr+1
        dey
        bne     ploop

        ;; Load font data into CHIP-8 memory
        ldx     #kFontDataSize-1
:       lda     font_data,x
        sta     CHIP8_MEMORY + FONT_ADDR,x
        dex
        bpl     :-

        rts

font_data:
        .byte   $F0, $90, $90, $90, $F0  ; '0' character
        .byte   $20, $60, $20, $20, $70  ; '1' character
        .byte   $F0, $10, $F0, $80, $F0  ; '2' character
        .byte   $F0, $10, $F0, $10, $F0  ; '3' character
        .byte   $90, $90, $F0, $10, $10  ; '4' character
        .byte   $F0, $80, $F0, $10, $F0  ; '5' character
        .byte   $F0, $80, $F0, $90, $F0  ; '6' character
        .byte   $F0, $10, $20, $40, $40  ; '7' character
        .byte   $F0, $90, $F0, $90, $F0  ; '8' character
        .byte   $F0, $90, $F0, $10, $F0  ; '9' character
        .byte   $F0, $90, $F0, $90, $90  ; 'A' character
        .byte   $E0, $90, $E0, $90, $E0  ; 'B' character
        .byte   $F0, $80, $80, $80, $F0  ; 'C' character
        .byte   $E0, $90, $90, $90, $E0  ; 'D' character
        .byte   $F0, $80, $F0, $80, $F0  ; 'E' character
        .byte   $F0, $80, $F0, $80, $80  ; 'F' character
        kFontDataSize = * - font_data
.endproc

times_5_table:
        .repeat 16, i
        .byte   i * 5
        .endrepeat


;;; ============================================================
;;; Keys

.proc ClearKeys
        lda     #$00
        sta     akd

        ldx     #$F
:       sta     keys,x
        dex
        bpl     :-

        rts
.endproc

;;; Updates `keys` states
.proc UpdateKeys
        ;; While $C010 yields "Any Key Down" (AKD), per Sather,
        ;; "Understanding the Apple IIe" pp. 7-15: "The AKD line goes
        ;; high while any matrix key is held down... For about 10
        ;; milliseconds after a key is pressed, the MPU will sense AKD
        ;; high at $C010 but will read outdated keyboard ASCII at
        ;; $C000-$C01F." So we can never check AKD to determine if
        ;; there is a new keypress and then immediately read KBD
        ;; or we can get stale data. We must rely on KBD to sense
        ;; a new keypress.

        lda     KBD
        bmi     :+

        ;; No new keypress. Clear the keyboard if released.
        ;; But don't touch the strobe unless we thought something was
        ;; down, else we might miss a keypress.
        bit     akd             ; did we think anything was down?
        bpl     ret             ; no, we're good
        lda     KBDSTRB         ; i.e. Any Key Down
        bpl     ClearKeys
        rts
:
        ;; New keypress. Clear previous state, note new key.
        pha
        sta     KBDSTRB         ; clear strobe
        jsr     ClearKeys       ; clear keypad state
        pla
        jsr     TranslateKey
        bmi     :+              ; not ours

        ;; Mark the key down
        tax
        lda     #$80
        sta     keys,x
        sta     akd
:

ret:    rts
.endproc

;;; Waits for new key press and its corresponding key release.
;;; https://www.laurencescotford.net/2020/07/19/chip-8-on-the-cosmac-vip-keyboard-input/
.proc WaitForKey
        ;; Wait for a key press
:       jsr     ServiceTimers
        lda     KBD
        bpl     :-
        jsr     TranslateKey
        bmi     :-              ; not ours
        pha                     ; A = key code

        ;; Wait for it to be released
        ;; (technically we wait for any key to be released)
:       jsr     ServiceTimers
        lda     KBDSTRB
        bmi     :-
        jsr     ClearKeys
        pla                     ; A = key code

        rts
.endproc

;;; N=0 if ours (and code 0-15), N=1 if not
.proc TranslateKey
        and     #$7F

        ;; Escape?
        cmp     #$1B
        bne     :+
        sta     KBDSTRB
        jmp     quit
:
        cmp     #'9'
        bne     :+
        jsr     PrevBorder
        lda     #$FF
        rts
:
        cmp     #'0'
        bne     :+
        jsr     NextBorder
        lda     #$FF
        rts
:
        cmp     #'['
        bne     :+
        jsr     PrevBG
        lda     #$FF
        rts
:
        cmp     #']'
        bne     :+
        jsr     NextBG
        lda     #$FF
        rts
:
        cmp     #','
        bne     :+
        jsr     PrevFG
        lda     #$FF
        rts
:
        cmp     #'.'
        bne     :+
        jsr     NextFG
        lda     #$FF
        rts
:
        ;; Convert to uppercase
        cmp     #'a'
        bcc     :+
        cmp     #'z'+1
        bcs     :+
        and     #$DF
:
        ;; Is it a keypad key?
        ldx     #$F
:       cmp     key_table,x
        beq     found
        dex
        bpl     :-
        rts                     ; not a key we care about, N=1

found:
        txa
        rts                     ; N=0

key_table:
        ;; COSMAC VIP hex keypad (index) to common QWERTY layout (value):
        ;;   1 2 3 4  >  1 2 3 C
        ;;   Q W E R  >  4 5 6 D
        ;;   A S D F  >  7 8 9 E
        ;;   Z X C V  >  A 0 B F
        ;; See https://tobiasvl.github.io/blog/write-a-chip-8-emulator/#keypad
        .byte   'X', '1', '2', '3'
        .byte   'Q', 'W', 'E', 'A'
        .byte   'S', 'D', 'Z', 'C'
        .byte   '4', 'R', 'F', 'V'
.endproc

;;; ============================================================
;;; Graphics

;;; 8-bit ROR, because DGR is annoying
.proc ROR8
        pha                     ; self-modified to `RTS` on IIe Card
        ror
        pla
        ror
        rts
.endproc

;;; --------------------------------------------------

;;; Mapping from CHIP-8 screen to Apple II Double-Low Resolution
X_OFFSET = (80 - CHIP8_SCREEN_WIDTH)/2
Y_OFFSET = (48 - CHIP8_SCREEN_HEIGHT)/2

;;; Clear border to passed color
;;; A = color
.proc DrawBorder
        sta     border_color    ; for later iteration
        sta     main_bits
        asl
        asl
        asl
        asl
        ora     main_bits
        sta     main_bits
        jsr     ROR8
        sta     aux_bits

        ;; NOTE: This takes longer than 4550 cycles (NTSC VBL) so we
        ;; carefully draw the border top to bottom to avoid tearing.

        jsr     WaitVBL

        sta     SET80STORE

        sta     HISCR
        lda     aux_bits
        jsr     top
        sta     LOWSCR
        lda     main_bits
        jsr     top

        sta     HISCR
        lda     aux_bits
        jsr     sides
        sta     LOWSCR
        lda     main_bits
        jsr     sides

        sta     HISCR
        lda     aux_bits
        jsr     bottom
        sta     LOWSCR
        lda     main_bits
        jsr     bottom

        sta     CLR80STORE
        rts

main_bits:      .byte   0
aux_bits:       .byte   0


top:
        ldy     #39
:
        sta     $400,y
        sta     $480,y
        sta     $500,y
        sta     $580,y

        dey
        bpl     :-

sides:
        ldx     #3
:
        sta     $600,x
        sta     $600+36,x
        sta     $680,x
        sta     $680+36,x
        sta     $700,x
        sta     $700+36,x
        sta     $780,x
        sta     $780+36,x
        sta     $428,x
        sta     $428+36,x
        sta     $4A8,x
        sta     $4A8+36,x
        sta     $528,x
        sta     $528+36,x
        sta     $5A8,x
        sta     $5A8+36,x
        sta     $628,x
        sta     $628+36,x
        sta     $6A8,x
        sta     $6A8+36,x
        sta     $728,x
        sta     $728+36,x
        sta     $7A8,x
        sta     $7A8+36,x
        sta     $450,x
        sta     $450+36,x
        sta     $4D0,x
        sta     $4D0+36,x
        sta     $550,x
        sta     $550+36,x
        sta     $5D0,x
        sta     $5D0+36,x

        dex
        bpl     :-
        rts

bottom:
        ldy     #39
:
        sta     $650,y
        sta     $6D0,y
        sta     $750,y
        sta     $7D0,y

        dey
        bpl     :-

        rts
.endproc

;;; --------------------------------------------------

;;; Clear CHIP-8 screen to background color

.proc ClearScreen
        jsr     WaitVBL

        sta     SET80STORE
        sta     LOWSCR

        ldx     #Y_OFFSET / 2
rloop:  lda     lores_table_lo,x
        sta     graph_ptr
        lda     lores_table_hi,x
        sta     graph_ptr+1

        ldy     #X_OFFSET / 2
cloop:
        sta     HISCR
        lda     bg_bits_aux
        sta     (graph_ptr),y

        sta     LOWSCR
        lda     bg_bits_main
        sta     (graph_ptr),y

        iny
        cpy     #(X_OFFSET + CHIP8_SCREEN_WIDTH)/2
        bne     cloop

        inx
        cpx     #(Y_OFFSET + CHIP8_SCREEN_HEIGHT)/2
        bne     rloop
        sta     CLR80STORE
        rts
.endproc


lores_table_lo:
        .lobytes $400, $480, $500, $580, $600, $680, $700, $780
        .lobytes $428, $4A8, $528, $5A8, $628, $6A8, $728, $7A8
        .lobytes $450, $4D0, $550, $5D0, $650, $6D0, $750, $7D0
lores_table_hi:
        .hibytes $400, $480, $500, $580, $600, $680, $700, $780
        .hibytes $428, $4A8, $528, $5A8, $628, $6A8, $728, $7A8
        .hibytes $450, $4D0, $550, $5D0, $650, $6D0, $750, $7D0

;;; --------------------------------------------------

.proc ExpandColorPatterns
        lda     bg_color
        asl
        asl
        asl
        asl
        ora     bg_color
        sta     bg_bits_main
        jsr     ROR8
        sta     bg_bits_aux

        lda     fg_color
        asl
        asl
        asl
        asl
        ora     fg_color
        sta     fg_bits_main
        jsr     ROR8
        sta     fg_bits_aux

        rts
.endproc

;;; --------------------------------------------------

;;; Inputs: X = x coordinate, Y = y coordinate, A = number of bytes of sprite data (at `addr_ptr`)
;;; Output: C=1 if any set pixels are changed to unset
.proc DrawSprite
        ;; Assert: X,Y wrapped to valid coordinates
        stx     sprite_x
        sty     sprite_y
        sta     sprite_rows

        jsr     SaveAddrPtr
        sta     SET80STORE

        ;; Clear collision flag
        lda     #0
        sta     collision

.if ::QUIRKS_DISP_VBL
        jsr     WaitVBL
.endif

        ;; --------------------------------------------------
        ;; Loop over rows (bytes in sprite)
yloop:
        ;; Set up row invariants
        lda     sprite_y
        jsr     _PrepareRow

        ;; Grab sprite data for this row
        ldy     #0
        lda     (addr_ptr),y
        beq     nexty           ; empty row

        ldx     sprite_x

        ;; Loop over columns (bits in byte)
xloop:
        asl                    ; shift in 0 so we know when we're done
        bcc     nextx          ; sprite bit is off or we're done, skip

        pha                     ; save remaining bits
        txa
        pha                     ; save x coordinate

        jsr     _TogglePixel

        pla                     ; restore X coordinate
        tax
        pla                     ; restore remaining bits

nextx:
        beq     nexty           ; nothing left in row
        inx
.if ::QUIRKS_CLIPPING
        cpx     #CHIP8_SCREEN_WIDTH
.endif
        bne     xloop

        ;; next row
nexty:
        inc     sprite_y

.if ::QUIRKS_CLIPPING
        ldy     sprite_y
        cpy     #CHIP8_SCREEN_HEIGHT
        beq     finish          ; off screen bottom, can early-exit
.endif

        jsr     IncAddrPtr
        dec     sprite_rows
        bne     yloop

finish:
        jsr     RestoreAddrPtr
        sta     CLR80STORE

        rol     collision       ; set C if collision
        rts

;;; --------------------------------------------------

;;; Set up drawing invariants for a single sprite row
;;; Input: A = Y coordinate
.proc _PrepareRow
.if !::QUIRKS_CLIPPING
        and     #CHIP8_SCREEN_HEIGHT-1
.endif

        ;; Center on screen
        clc
        adc     #Y_OFFSET

        ;; Account for 2 pixels per byte
        lsr                     ; /= 2, C = top/bottom
        tay                     ; Y = effective row

        ;; Masks for top/bottom pixels
        lda     #%00001111
        bcc     :+
        lda     #%11110000
:       sta     mask1
        eor     #$FF            ; need to complement as well
        sta     mask2

        ;; Set up row pointer
        lda     lores_table_lo,y
        sta     graph_ptr
        lda     lores_table_hi,y
        sta     graph_ptr+1

        rts
.endproc

;;; --------------------------------------------------

;;; Input: A = col
.proc _TogglePixel
.if !::QUIRKS_CLIPPING
        and     #CHIP8_SCREEN_WIDTH-1
.endif

        ;; Center on screen
        clc
        adc     #X_OFFSET

        ;; --------------------------------------------------
        ;; Scale X coordinate, set up page and colors

        lsr                     ; /= 2, C = even/odd col
        tay                     ; Y = effective column

        ;; Which page?
        sta     LOWSCR
        lda     bg_bits_main
        ldx     fg_bits_main
        bcs     :+
        sta     HISCR           ; even, so write to aux memory
        lda     bg_bits_aux
        ldx     fg_bits_aux
:
        sta     bg
        stx     fg

        ;; --------------------------------------------------
        ;; Modify the graphics screen

        ;; Check for collision - is current pixel FG or BG?
        lda     (graph_ptr),y
        eor     bg              ; leaves "our" nibble 0 if bg
        and     mask1
        beq     set

        ;; clear
        sec                     ; set flag
        ror     collision

        lda     bg
        jmp     modify

        ;; set
set:
        lda     fg

modify:
        ;; A = color bits to emplace
        pha
        lda     (graph_ptr),y   ; make a hole
        and     mask2
        sta     (graph_ptr),y

        pla
        and     mask1           ; fill it
        ora     (graph_ptr),y
        sta     (graph_ptr),y

        ;; restore banking
        sta     LOWSCR

ret:    rts
.endproc

.endproc

;;; ============================================================

;;; Not on ZP since this is used infrequently
border_color:   .byte   COLOR_BORDER

.proc PrevBorder
        lda     border_color
        sec
        sbc     #1
        and     #$F
        sta     border_color
        jmp     DrawBorder
.endproc

.proc NextBorder
        lda     border_color
        clc
        adc     #1
        and     #$F
        sta     border_color
        jmp     DrawBorder
.endproc

.proc PrevBG
        jsr     ScreenToBitmap

        ldx     bg_color
:       dex
        txa
        and     #$F
        tax
        cpx     fg_color
        beq     :-
        stx     bg_color

        jsr     ExpandColorPatterns
        jsr     ClearScreen
        jmp     BitmapToScreen
.endproc

.proc NextBG
        jsr     ScreenToBitmap

        ldx     bg_color
:       inx
        txa
        and     #$F
        tax
        cpx     fg_color
        beq     :-
        stx     bg_color

        jsr     ExpandColorPatterns
        jsr     ClearScreen
        jmp     BitmapToScreen
.endproc

.proc PrevFG
        jsr     ScreenToBitmap

        ldy     fg_color
:       dey
        tya
        and     #$F
        tay
        cpy     bg_color
        beq     :-
        sty     fg_color

        jsr     ExpandColorPatterns
        jmp     BitmapToScreen
.endproc

.proc NextFG
        jsr     ScreenToBitmap

        ldy     fg_color
:       iny
        tya
        and     #$F
        tay
        cpy     bg_color
        beq     :-
        sty     fg_color

        jsr     ExpandColorPatterns
        jmp     BitmapToScreen
.endproc

;;; Populate CHIP8_BITMAP from the DGR screen
.proc ScreenToBitmap
        sta     SET80STORE
        ldx     #0              ; offset into bitmap
        ldy     #0              ; Y cordinate
yloop:
        ;; Determine effective Y and masks
        tya
        pha
        clc
        adc     #Y_OFFSET
        lsr                     ; C = top (0) or bottom (1)
        tay                     ; effective Y

        lda     #%00001111
        bcc     :+
        lda     #%11110000
:       sta     mask1

        lda     lores_table_lo,y
        sta     graph_ptr
        lda     lores_table_hi,y
        sta     graph_ptr+1

        ldy     #0              ; X coordinate
xloop:
        ;; Determine effective X and page
        tya
        pha
        clc
        adc     #X_OFFSET
        lsr                     ; C = aux (0) or main (1)
        tay                     ; effective X

        bit     HISCR
        lda     bg_bits_aux
        bcc     :+
        bit     LOWSCR
        lda     bg_bits_main
:
        ;; Read out the pixel and shift into bitmap
        clc
        eor     (graph_ptr),y
        and     mask1
        beq     :+
        sec
:       ror     CHIP8_BITMAP,x  ; shift C into bitmap

        ;; Next X
        pla                     ; X coordinate
        tay
        iny
        tya                     ; done 8 bits?
        and     #7
        bne     :+
        inx                     ; next byte of bitmap
:       cpy     #CHIP8_SCREEN_WIDTH
        bne     xloop

        ;; Next Y
        pla                     ; Y coordinate
        tay
        iny
        cpy     #CHIP8_SCREEN_HEIGHT
        bne     yloop
        sta     CLR80STORE

        rts
.endproc

;;; Apply `CHIP8_BITMAP` to the DGR screen
.proc BitmapToScreen
        sta     SET80STORE
        ldx     #0              ; offset into bitmap
        ldy     #0              ; Y coordinate
yloop:
        ;; Determine effective Y and masks
        tya
        pha
        clc
        adc     #Y_OFFSET
        lsr                     ; C = top (0) or bottom (1)
        tay                     ; effective Y

        lda     #%00001111
        bcc     :+
        lda     #%11110000
:       sta     mask1           ; bits to set
        eor     #$FF
        sta     mask2           ; bits to keep

        lda     lores_table_lo,y
        sta     graph_ptr
        lda     lores_table_hi,y
        sta     graph_ptr+1

        ldy     #0              ; X coordinate
xloop:
        ;; Determine effective X and page
        tya
        pha

        lsr     CHIP8_BITMAP,x  ; shift C out of bitmap
        bcc     nextx           ; background, no-op

        clc
        adc     #X_OFFSET
        lsr                     ; C = aux (0) or main (1)
        tay                     ; effective X

        bit     HISCR
        lda     fg_bits_aux
        bcc     :+
        bit     LOWSCR
        lda     fg_bits_main
:
        pha
        lda     (graph_ptr),y   ; make a hole
        and     mask2
        sta     (graph_ptr),y

        pla
        and     mask1           ; fill it
        ora     (graph_ptr),y
        sta     (graph_ptr),y

        ;; Next X
nextx:
        pla                     ; X coordinate
        tay
        iny
        tya                     ; done 8 bits?
        and     #7
        bne     :+
        inx                     ; next byte of bitmap
:       cpy     #CHIP8_SCREEN_WIDTH
        bne     xloop

        ;; Next y
        pla                     ; Y coordinate
        tay
        iny
        cpy     #CHIP8_SCREEN_HEIGHT
        bne     yloop
        sta     CLR80STORE

        rts
.endproc

;;; ============================================================
;;; Pseudorandom Number Generation

;;; From https://www.apple2.org.za/gswv/a2zine/GS.WorldView/v1999/Nov/Articles.and.Reviews/Apple2RandomNumberGenerator.htm
;;; By David Empson

;;; NOTE: low bit of N and high bit of N+2 are coupled

.scope PRNGState
R1:     .byte  0
R2:     .byte  0
R3:     .byte  0
R4:     .byte  0
.endscope

.proc Random
        ror PRNGState::R4       ; Bit 25 to carry
        lda PRNGState::R3       ; Shift left 8 bits
        sta PRNGState::R4
        lda PRNGState::R2
        sta PRNGState::R3
        lda PRNGState::R1
        sta PRNGState::R2
        lda PRNGState::R4       ; Get original bits 17-24
        ror                     ; Now bits 18-25 in ACC
        rol PRNGState::R1       ; R1 holds bits 1-7
        eor PRNGState::R1       ; Seven bits at once
        ror PRNGState::R4       ; Shift right by one bit
        ror PRNGState::R3
        ror PRNGState::R2
        ror
        sta PRNGState::R1
        rts
.endproc

.proc InitRand
        lda $4E                 ; TODO: Improve this
        sta PRNGState::R1
        sta PRNGState::R2
        stx PRNGState::R3
        sty PRNGState::R4
        ldx #$20                ; Generate a few random numbers
InitLoop:
        jsr Random              ; to kick things off
        dex
        bne InitLoop
        rts
.endproc

;;; ============================================================

.proc SetTextMode
        sta     CLR80VID
        sta     DHIRESOFF
        sta     TXTSET
        jsr     SETVID
        jsr     SETKBD
        jsr     SETNORM
        jsr     INIT
        jsr     HOME
        rts
.endproc

;;; ============================================================

.proc BadInstruction
        jsr     SetTextMode

        ldx     #0
:       lda     msg1,x
        beq     :+
        ora     #$80
        jsr     COUT
        inx
        bne     :-              ; always
:
        lda     instr+1
        jsr     PRBYTE
        lda     instr
        jsr     PRBYTE

        ldx     #0
:       lda     msg2,x
        beq     :+
        ora     #$80
        jsr     COUT
        inx
        bne     :-              ; always
:
        lda     pc_ptr+1
        and     #ADDR_MASK_HI
        jsr     PRBYTE
        lda     pc_ptr
        jsr     PRBYTE

        ;; Wait for keypress
        jsr     CROUT
        sta     KBDSTRB
:       lda     KBD
        bpl     :-
        sta     KBDSTRB

        jmp     Exit

msg1:    .byte   "Bad instruction ", 0
msg2:    .byte   " at address ", 0

.endproc

;;; ============================================================

.proc Exit
        jsr     SetTextMode

        ;; IIc: Disable VBL
        lda     ZIDBYTE         ; IIc = $00
        bne     :+
        sta     IOUDISON
        bit     DISVBL
        cli                     ; back to normal
:
        jmp     quit
.endproc

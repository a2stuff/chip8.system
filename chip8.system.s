;;; ============================================================
;;; CHIP-8 Interpreter
;;; ============================================================

        .setcpu "6502"

        .include "apple2.inc"
        .include "longbranch.mac"
        .include "prodos.inc"

        .org    $2000

;;; ============================================================
;;; Memory map

;;;              Main           Aux
;;;          :             : :             :
;;;          |             | |             |
;;;          |             | | (unused)    |
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

CHIP8_STACK  := $5000

;;; ============================================================
;;; Interpreter protocol
;;; http://www.easy68k.com/paulrsm/6502/PDOS8TRM.HTM#5.1.5.1

        jmp     start
        .byte   $EE, $EE        ; signature
        .byte   65              ; pathname buffer length ($2005)
str_path:
        .res    65, 0

SYS_PATH := $280

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
data_buffer:    .addr   BUF
request_count:  .word   BUF_SIZE
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
        jsr     INIT
        jsr     HOME

        ;; ----------------------------------------
        ;; Pathname passed?

        lda     str_path
        bne     load_file

        ;; TODO: Bundle a default program instead?

quit:
        ;; Quit back to ProDOS
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
        MLI_CALL OPEN, open_params
        bcs     fail
        lda     open_params::ref_num
        sta     read_params::ref_num
        sta     close_params::ref_num

read_more:
        MLI_CALL READ, read_params
        bcs     fail

        MLI_CALL CLOSE, close_params
        bcs     fail

;;; ============================================================
;;; Interpreter

        ;; TODO: Configure the interpreter initial state
        ;; TODO: Write the interpreter

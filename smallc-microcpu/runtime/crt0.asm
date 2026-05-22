;
; Standalone crt0 template for Small-C microcpu programs.
; The compiler currently emits equivalent startup code directly.
; _main returns in v0; the halt loop preserves it for the test runner.
; The stack is a 512-byte block appended after the program image.
;

include ../../asm/include/pseudo.inc
include microcpu_cc.inc

org $0000

__smallc_start:
	set	sp, __smallc_stack_top
	jsr	_main
__test_halt:
	b	__test_halt

align 1
__smallc_stack:
	ds	512
__smallc_stack_top:

;
; Standalone crt0 template for Small-C microcpu programs.
; The compiler currently emits equivalent startup code directly.
;

include ../../asm/include/pseudo.inc
include microcpu_cc.inc

org $0000

__smallc_start:
	set	sp, __smallc_stack_top
	jsr	_main
__smallc_halt:
	b	__smallc_halt

align 1
__smallc_stack:
	ds	512
__smallc_stack_top:

;
; Object-mode crt0 for Small-C microcpu tests.
;

include ../../asm/include/pseudo.inc

extern _main
extern __sc_stktop

__smallc_start:
	set	sp, __sc_stktop
	jsr	_main
__test_halt:
	b	__test_halt

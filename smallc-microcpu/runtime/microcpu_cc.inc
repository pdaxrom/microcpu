;
; Small-C microcpu backend helper macros.
;

	macro	cc_push
	str	#1, sp, 0
	sub	sp, sp, 2
	endm

	macro	cc_pop
	add	sp, sp, 2
	ldr	#1, sp, 0
	endm

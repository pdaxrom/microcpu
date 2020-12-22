	include ../include/pseudo.inc
	include ../include/devmap.inc

	org	$100

begin	set	sp, $07fe
	set	v0, banner
	bsr	VEC_PUTSTR
	set	v0, $12ab
	bsr	printhex

	inv	v0, v0
	bsr	printhex

	set	v0, $ffff
;	set	v1, $1
	xor	v0, v0, 2
	bsr	printhex

	xor	v0, v0, 2
	bsr	printhex

	set	v0, 16

cccc	bsr	printhex
	sub	v0, v0, 1
	bne	cccc, v0, 0

cccc1	set	v0, nl
	bsr	VEC_PUTSTR

; test timer

	set	v1, TIMER_ADDR

	ldr	v0, v1, 0
	bsr	printhex

	set	v0, nl
	bsr	VEC_PUTSTR

	ldr	v0, v1, 2
	bsr	printhex

	set	v0, nl
	bsr	VEC_PUTSTR

; start timer

	set	v2, $ffff
	str	v2, v1, 0

	ldr	v2, v1, 0
	ldr	v0, v1, 0
	sub	v0, v0, v2
	bsr	printhex

	set	v0, nl
	bsr	VEC_PUTSTR

timeloop ldr	v0, v1, 0
	bsr	printhex

	set	v0, nl
	bsr	VEC_PUTSTR

	ldrl	v0, v1, 2
	maskeq	timeloop, v0, 2

	bsr	printhex

	set	v0, nl
	bsr	VEC_PUTSTR

	ldr	v0, v1, 0
	bsr	printhex

	set	v0, nl
	bsr	VEC_PUTSTR

	ldr	v0, v1, 2
	bsr	printhex

	set	v0, nl
	bsr	VEC_PUTSTR


; main loop

mainloop bsr	VEC_GETCHAR
	bsr	VEC_PUTCHAR
	b	mainloop

printhex proc
	push	lr
	push	v0
	shr	v0, v0, 8
	bsr	printhex8
	pop	v0
	bsr	printhex8
	pop	lr
	rts
	endp

printhex8 proc
	push	lr
	push	v0
	push	v1
	set	v1, nums
	seth	v0, 0
	push	v0
	shr	v0, v0, 4
	add	v0, v1, v0
	ldrl	v0, v0, 0
	bsr	VEC_PUTCHAR
	pop	v0
	and	v0, v0, 15
	add	v0, v1, v0
	ldrl	v0, v0, 0
	bsr	VEC_PUTCHAR
	pop	v1
	pop	v0
	pop	lr
	rts
nums	db	'0123456789ABCDEF'
	endp

banner	db	10, 13, "Welcome to pdaXrom uCPU board!", 10, 13, 0

nl	db	10, 13, 0

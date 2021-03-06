	include ../include/pseudo.inc
	include ../include/devmap.inc

	org	$100

	b	begin

isr	sub	sp, sp, 14
	push	v0
	push	v1

	set	v1, counter
	ldr	v0, v1, 0
	add	v0, v0, 1
	str	v0, v1, 0

	set	v1, TIMER_ADDR
	ldrl	v0, v1, 2	; reset timer interrupt flag
	set	v0, $ffff	;
	str	v0, v1, 0	; restart timer

	pop	v1
	pop	v0
	add	sp, sp, 14
	swu

begin	set	sp, $07fe

; set super vector
	set	v1, 2
	set	v2, $80B0
	str	v2, v1, 0

	set	v1, TIMER_ADDR
	set	v0, $ffff	;
	str	v0, v1, 0	; start timer

;	set	v0, tosup
;	bsr	VEC_PUTSTR


loop	set	v0, counter
	ldr	v0, v0, 0
	bsr	printhex

	set	v0, nl
	bsr	VEC_PUTSTR
	b	loop

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

nl	db	10, 13, 0

counter	dw	0
	dw	0

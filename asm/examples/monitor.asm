	include ../include/pseudo.inc
	include ../include/devmap.inc

	org	$100

	b	main

isr	proc
	sub	sp, sp, 14
	push	v0
	push	v1

	set	v1, TIMER_ADDR
	ldrl	v0, v1, 2	; reset timer interrupt flag
	maskeq	next, v0, 1
	set	v0, timer_i
	bsr	VEC_PUTSTR

next	pop	v1
	pop	v0
	add	sp, sp, 14
	swu

timer_i	db	'Timer interrupt ', 10, 13, 0
memap_i	db	'Memmapping interrupt ', 10, 13, 0
sws_i	db	'SWS interrupt ', 10, 13, 0
	endp

main	proc
	set	sp, $07fe
	set	v0, banner
	bsr	VEC_PUTSTR

; main loop

loop	set	v1, lastch
	bsr	gethex
	str	v0, v1, 2
	ldr	v0, v1, 0
	set	v2, '.'
	bne	action, v0, v2
	bsr	gethex
	str	v0, v1, 4
action	ldr	v0, v1, 0
	setl	v2, 'Z'
	beq	dump, v0, v2
	b	loop
dump	ldr	v2, v1, 4
	ldr	v1, v1, 2
dump1	mov	v0, v1
	bsr	printhex
	setl	v0, ' '
	bsr	VEC_PUTCHAR
	set	v3, 16
dump2	ldrl	v0, v1, 0
	bsr	printhex8
	setl	v0, ' '
	bsr	VEC_PUTCHAR
	add	v1, v1, 1
	beq	dump3, v1, v2
	sub	v3, v3, 1
	bne	dump2, v3, 0
	set	v0, nl
	bsr	VEC_PUTSTR
	b	dump1
dump3	b	loop
	endp

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

gethex	proc
	push	lr
	push	v1
	push	v2
	push	v3

	seth	v0, 0
	set	v1, lastch
loop	bsr	VEC_GETCHAR
	bsr	VEC_PUTCHAR
	str	v0, v1, 0
	set	v2, '0'
	sub	v0, v0, v2
	bltu	okay, v0, 10
	sub	v0, v0, 7
	bltu	exit, v0, 10
	bgtu	exit, v0, 15
okay	shl	v3, v3, 4
	or	v3, v3, v0
	b	loop

exit	mov	v0, v3
	pop	v3
	pop	v2
	pop	v1
	pop	lr
	rts
	endp

banner	db	10, 13, "pdaXrom monitor", 10, 13, 0
nl	db	10, 13, 0
lastch	dw	0
saddr	dw	0
eaddr	dw	0

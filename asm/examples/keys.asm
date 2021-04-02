LED_R		equ	1
LED_G		equ	2
LED_B		equ	4

	include ../include/pseudo.inc
	include ../include/devmap.inc

	org	$800

begin	set	sp, $07fe

	set	v0, t_1
	jsr	VEC_PUTSTR

	setl	v0, 6
	bsr	get_key
	bsr	printhex8

	set	v0, t_5
	jsr	VEC_PUTSTR

stop	jmp	VEC_RESET

get_key	proc
	push	lr
	push	v1
	push	v2
	push	v3
	push	v4
	seth	v0, 0
	mov	v4, v0
	clr	v2
	set	v3, 8
	set	v1, GPIO_ADDR
loop	mov	v0, v3
	or	v0, v0, v4
	jsr	VEC_SETOUTREG
	ldrl	v0, v1, 0
	shr	v0, v0, 4
	bne	key, v0, 0
	add	v2, v2, 4
	shl	v3, v3, 1
	seth	v3, 0
	bne	loop, v3, 0
	clr	v0
exit	set	v1, kmap
	ldrl	v0, v1, v0
	pop	v4
	pop	v3
	pop	v2
	pop	v1
	pop	lr
	rts
key	add	v2, v2, 1
	shr	v0, v0, 1
	bne	key, v0, 0
	mov	v0, v2
	b	exit
kmap	db	$ff
	db	$00, $01, $04, $07
	db	$0a, $02, $05, $08
	db	$0b, $03, $06, $09
	db	$0f, $0e, $0d, $0c
	db	$10, $11, $12, $13
	align	1
	endp

delay	proc
	push	v0
	push	v1
loop	sub	v0, v0, 1
	set	v1, 0
loop1	sub	v1, v1, 1
	bne	loop1, v1, 0
	bne	loop, v0, 0
	pop	v1
	pop	v0
	rts
	endp

dump	proc
	push	lr
	push	v0
	bsr	printhex8
	set	v0, nl
	jsr	VEC_PUTSTR
	pop	v0
	pop	lr
	rts
	endp

t_1	db	10, 13, 'Init', 10, 13, 0
t_5	db	10, 13, 'Stop'
nl	db	10, 13, 0

	align	2


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
	jsr	VEC_PUTCHAR
	pop	v0
	and	v0, v0, 15
	add	v0, v1, v0
	ldrl	v0, v0, 0
	jsr	VEC_PUTCHAR
	pop	v1
	pop	v0
	pop	lr
	rts
nums	db	'0123456789ABCDEF'
	endp

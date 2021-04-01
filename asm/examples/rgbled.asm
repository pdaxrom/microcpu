;
; HCMS matrix display
;
; GPIO 0 - DIN
; GPIO 2 - CLK
; GPIO 5 - REG_LATCH
;

LED_R		equ	1
LED_G		equ	2
LED_B		equ	4

	include ../include/pseudo.inc
	include ../include/devmap.inc

	org	$800

begin	set	sp, $07fe

	set	v0, t_1
	jsr	VEC_PUTSTR

	setl	v0, $FF^LED_R
	jsr	VEC_SETOUTREG

	set	v0, 30
	bsr	delay

	setl	v0, $FF^LED_G
	jsr	VEC_SETOUTREG

	set	v0, 30
	bsr	delay

	setl	v0, $FF^LED_B
	jsr	VEC_SETOUTREG

	set	v0, 30
	bsr	delay

	set	v0, t_5
	jsr	VEC_PUTSTR

stop	jmp	VEC_RESET

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

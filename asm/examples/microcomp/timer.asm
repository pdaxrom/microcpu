	macro nop
	mov	v0,v0
	endm

	macro bsr
	mov	lr, pc
	b	#1
	endm

	macro rts
	add	pc, lr, 3
	endm

	macro push
	str	#1, sp, 0
	sub	sp, sp, 2
	endm

	macro pop
	add	sp, sp, 2
	ldr	#1, sp, 0
	endm

	macro set
	setl	#1, #2
	seth	#1, /#2
	endm

	macro	beq
	ne	#2, #3
	b	#1
	endm

	macro	bne
	eq	#2, #3
	b	#1
	endm

	macro	maskeq
	mne	#2, #3
	b	#1
	endm

	macro	maskne
	meq	#2, #3
	b	#1
	endm

UART_ADDR	equ	$e6b0
TIMER_ADDR	equ	$e6d8

VEC_RESET	equ	$0000
VEC_INTR	equ	$0002
VEC_MEMERR	equ	$0004
VEC_GETCHAR	equ	$0006
VEC_PUTCHAR	equ	$0008
VEC_PUTSTR	equ	$000a

	org	$100

	b	begin

isr	sub	sp, sp, 14
	set	v1, TIMER_ADDR
	ldrl	v0, v1, 2

;	set	v0, tosup
;	bsr	VEC_PUTSTR

	set	v0, counter
	ldr	v0, v0, 0
	bsr	printhex
	set	v0, nl
	bsr	VEC_PUTSTR

	set	v1, counter
	ldr	v0, v1, 0
	add	v0, v0, 1
	str	v0, v1, 0

	set	v1, TIMER_ADDR
	set	v0, $ffff
	str	v0, v1, 0

	add	sp, sp, 14
	swu

begin	set	sp, $07fe

; set super vector
	set	v1, 2
	set	v2, $80B0
	str	v2, v1, 0

	set	v1, TIMER_ADDR
	set	v0, $ffff
	str	v0, v1, 0

stop	b	stop

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

tosup	db	10, 13, "Switch to super mode", 10, 13, 0
tousr	db	10, 13, "Switch to user  mode", 10, 13, 0
okay	db	10, 13, "Hello from user mode", 10, 13, 0

nl	db	10, 13, 0

counter	dw	0
	dw	0

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

isr	set	v0, tousr
	bsr	VEC_PUTSTR

	swu

begin	set	sp, $07fe

; set super vector
	set	v1, 2
	set	v2, $80B0
	str	v2, v1, 0

	set	v0, tosup
	bsr	VEC_PUTSTR

	sws

	set	v0, okay
	bsr	VEC_PUTSTR

stop	b	VEC_RESET

tosup	db	10, 13, "Switch to super mode", 10, 13, 0
tousr	db	10, 13, "Switch to user  mode", 10, 13, 0
okay	db	10, 13, "Hello from user mode", 10, 13, 0

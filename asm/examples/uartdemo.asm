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

UART_ADDR	equ	$e6b0
TIMER_ADDR	equ	$e6d8

begin	set	sp, $03fe
	set	v0, banner
	bsr	printstr
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
	beq	cccc1
	b	cccc

cccc1	set	v0, nl
	bsr	printstr

; test timer

	set	v1, TIMER_ADDR

	ldr	v0, v1, 0
	bsr	printhex

	set	v0, nl
	bsr	printstr

	ldr	v0, v1, 2
	bsr	printhex

	set	v0, nl
	bsr	printstr

; start timer

	set	v2, $ffff
	str	v2, v1, 0

	ldr	v2, v1, 0
	ldr	v0, v1, 0
	sub	v0, v0, v2
	bsr	printhex

	set	v0, nl
	bsr	printstr

timeloop ldr	v0, v1, 0
	bsr	printhex

	set	v0, nl
	bsr	printstr

	ldrl	v0, v1, 2
	tst	v0, 2
	beq	timeloop

	bsr	printhex

	set	v0, nl
	bsr	printstr

	ldr	v0, v1, 0
	bsr	printhex

	set	v0, nl
	bsr	printstr

	ldr	v0, v1, 2
	bsr	printhex

	set	v0, nl
	bsr	printstr


; main loop

mainloop bsr	getchar
	bsr	putchar
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
	bsr	putchar
	pop	v0
	and	v0, v0, 15
	add	v0, v1, v0
	ldrl	v0, v0, 0
	bsr	putchar
	pop	v1
	pop	v0
	pop	lr
	rts
nums	db	'0123456789ABCDEF'
	endp

printstr proc
	push	lr
	push	v0
	push	v1
	mov	v1, v0
	seth	v0, 0
.1	ldrl	v0, v1, 0
	cmp	v0, 0
	beq	.2
	bsr	putchar
	add	v1, v1, 1
	b	.1
.2	pop	v1
	pop	v0
	pop	lr
	rts
	endp

putchar	proc
	push	v1
	push	v2
	set	v1, UART_ADDR
.1	ldrl	v2, v1, 0
	and	v2, v2, 2
	beq	.2
	b	.1
.2	strl	v0, v1, 1
	pop	v2
	pop	v1
	rts
	endp

getchar	proc
	push	v1
	set	v1, UART_ADDR
	seth	v0, 0
.1	ldrl	v0, v1, 0
	and	v0, v0, 1
	beq	.1
	ldrl	v0, v1, 1
	pop	v1
	rts
	endp

banner	db	10, 13, "Welcome to pdaXrom uCPU board!", 10, 13, 0

nl	db	10, 13, 0

	ds	$400-*

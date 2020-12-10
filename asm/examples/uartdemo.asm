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
	strh	#1, sp, 0
	strl	#1, sp, 1
	sub	sp, sp, 2
	endm

	macro pop
	add	sp, sp, 2
	ldrh	#1, sp, 0
	ldrl	#1, sp, 1
	endm

	macro set
	seth	#1, /#2
	setl	#1, #2
	endm

UART_ADDR	equ	$e6b0

begin	set	sp, $01fe
	set	v0, banner
	bsr	printstr
mainloop bsr	getchar
	bsr	putchar
	b	mainloop

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

banner	db	"Welcome to pdaXrom ucpu board!", 10, 13, 0

	ds	$100-*

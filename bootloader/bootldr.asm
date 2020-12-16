;
; BOOTROM for microcpu
; (c) sashz <sashz@pdaXrom.org>, 2020
;

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

	org	$0

	b	begin
	b	begin		; reserved for external interrupt
	b	begin		; reserved for memory access error
	b	getchar
	b	putchar
	b	printstr
;	b	printhex8
;	b	printhex

begin	set	sp, $07fe
	set	v0, banner
	bsr	printstr

	seth	v1, 0
mainloop bsr	getchar
	setl	v1, 'L'
	cmp	v0, v1
	beq	cmd_load
	setl	v1, 'S'
	cmp	v0, v1
	beq	cmd_save
	setl	v1, 'G'
	cmp	v0, v1
	beq	cmd_go
	setl	v1, 'E'
	cmp	v0, v1
	beq	cmd_exit
	b	mainloop
cmd_exit b	begin

cmd_load proc
	bsr	get_word
	mov	v1, v0
	bsr	get_word
	mov	v2, v0

loop	bsr	getchar
	strl	v0, v1, 0
	add	v1, v1, 1
	cmp	v1, v2
	beq	begin
	b	loop
	endp

cmd_save proc
	bsr	get_word
	mov	v1, v0
	bsr	get_word
	mov	v2, v0

loop	ldrl	v0, v1, 0
	bsr	putchar
	add	v1, v1, 1
	cmp	v1, v2
	beq	begin
	b	loop
	endp

cmd_go	proc
	bsr	get_word
	mov	pc, v0
	endp

get_word proc
	sub	sp, sp, 4
	str	lr, sp, 4
	str	v1, sp, 2
	bsr	getchar
	mov	v1, v0
	bsr	getchar
	movh	v0, v1
	ldr	v1, sp, 2
	ldr	lr, sp, 4
	add	sp, sp, 4
	rts
	endp

;printhex proc
;	sub	sp, sp, 4
;	str	lr, sp, 4
;	str	v0, sp, 2
;	shr	v0, v0, 8
;	bsr	printhex8
;	ldr	v0, sp, 2
;	bsr	printhex8
;	ldr	lr, sp, 4
;	add	sp, sp, 4
;	rts
;	endp

;printhex8 proc
;	sub	sp, sp, 8
;	str	lr, sp, 8
;	str	v0, sp, 6
;	str	v1, sp, 4
;	set	v1, nums
;	seth	v0, 0
;	str	v0, sp, 2
;	shr	v0, v0, 4
;	add	v0, v1, v0
;	ldrl	v0, v0, 0
;	bsr	putchar
;	ldr	v0, sp, 2
;	and	v0, v0, 15
;	add	v0, v1, v0
;	ldrl	v0, v0, 0
;	bsr	putchar
;	ldr	v1, sp, 4
;	ldr	v0, sp, 6
;	ldr	lr, sp, 8
;	add	sp, sp, 8
;	rts
;nums	db	'0123456789ABCDEF'
;	endp

printstr proc
	sub	sp, sp, 6
	str	lr, sp, 6
	str	v0, sp, 4
	str	v1, sp, 2
	mov	v1, v0
	seth	v0, 0
.1	ldrl	v0, v1, 0
	cmp	v0, 0
	beq	.2
	bsr	putchar
	add	v1, v1, 1
	b	.1
.2	ldr	v1, sp, 2
	ldr	v0, sp, 4
	ldr	lr, sp, 6
	add	sp, sp, 6
	rts
	endp

putchar	proc
	sub	sp, sp, 2
	str	v1, sp, 2
	str	v2, sp, 0
	set	v1, UART_ADDR
.1	ldrl	v2, v1, 0
	and	v2, v2, 2
	beq	.2
	b	.1
.2	strl	v0, v1, 1
	ldr	v2, sp, 0
	ldr	v1, sp, 2
	add	sp, sp, 2
	rts
	endp

getchar	proc
	str	v1, sp, 0
	set	v1, UART_ADDR
	seth	v0, 0
.1	ldrl	v0, v1, 0
	and	v0, v0, 1
	beq	.1
	ldrl	v0, v1, 1
	ldr	v1, sp, 0
	rts
	endp

banner	db	10, 13, "Z/pdaXrom UART loader", 10, 13, 0

	ds	$800-*

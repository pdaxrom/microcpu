;
; BOOTROM for microcpu
; (c) sashz <sashz@pdaXrom.org>, 2020
;

	include ../asm/include/pseudo.inc
	include ../asm/include/devmap.inc

	org	$0

	b	begin
	b	begin		; reserved for external interrupt
	b	begin		; reserved for memory access error
	b	getchar
	b	putchar
	b	printstr

begin	set	sp, $07fe
	set	v0, banner
	bsr	printstr

	seth	v1, 0
mainloop bsr	getchar
	setl	v1, 'L'
	beq	cmd_load, v0, v1
	setl	v1, 'S'
	beq	cmd_save, v0, v1
	setl	v1, 'G'
	beq	cmd_go, v0, v1
	setl	v1, 'E'
	beq	cmd_exit, v0, v1
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
	bne	loop, v1, v2
	b	begin
	endp

cmd_save proc
	bsr	get_word
	mov	v1, v0
	bsr	get_word
	mov	v2, v0

loop	ldrl	v0, v1, 0
	bsr	putchar
	add	v1, v1, 1
	bne	loop, v1, v2
	b	begin
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

printstr proc
	sub	sp, sp, 6
	str	lr, sp, 6
	str	v0, sp, 4
	str	v1, sp, 2
	mov	v1, v0
	seth	v0, 0
.1	ldrl	v0, v1, 0
	beq	.2, v0, 0
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
	maskne	.1, v2, 2
	strl	v0, v1, 1
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
	maskeq	.1, v0, 1
	ldrl	v0, v1, 1
	ldr	v1, sp, 0
	rts
	endp

banner	db	10, 13, "Z/pdaXrom UART loader", 10, 13, 0

	ds	$800-*

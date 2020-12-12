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

begin	set	sp, $03fe
	set	v0, banner
	bsr	printstr

	set	v1, 0		; bge
	set	v2, 0
	bsr	compare

	set	v1, 0		; ble
	set	v2, $1234
	bsr	compare

	set	v1, $1234	; bge
	set	v2, 0
	bsr	compare

	set	v1, $1234	; ble
	set	v2, $3456
	bsr	compare

	set	v1, $fff0	; ble
	set	v2, $3456
	bsr	compare

	set	v1, $3456	; bge
	set	v2, $face
	bsr	compare

	set	v1, $8123	; ble
	set	v2, $face
	bsr	compare

	set	v1, $face	; bge
	set	v2, $8123
	bsr	compare

	set	v0, banner2
	bsr	printstr

stop	b	stop

compare	proc
	push	lr
	cmp	v1, v2
;	beq	.eq
;	bcs	.cs
	bge	.ge
	ble	.le
	set	v0, text_xyz
	b	print
.eq	set	v0, text_beq
	b	print
.cs	set	v0, text_bcs
	b	print
.le	set	v0, text_ble
	b	print
.ge	set	v0, text_bge
print	bsr	printstr
	pop	lr
	rts
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

printhex proc
	push	lr
	push	v0
	shr	v0, v0, 8
	bsr	printhex2
	pop	v0
	bsr	printhex2
	pop	lr
	rts
	endp

printhex2 proc
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

banner2	db	10, 13, "STOP stop stop!!!", 10, 13, 0

text_ble db	"ble", 10, 13, 0

text_bge db	"bge", 10, 13, 0

text_bcs db	"bcs", 10, 13, 0

text_beq db	"beq", 10, 13, 0

text_xyz db	"xyz", 10, 13, 0

	ds	$400-*

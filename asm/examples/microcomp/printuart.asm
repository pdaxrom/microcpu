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

	org		$100

begin:
	set	sp, $7fe

	set	v1, text
	seth	v0, 0
loop:
	ldrl	v0, v1, 0
	beq	loopexit, v0, 0
	bsr	printnum
	add	v1, v1, 1
	b	loop
loopexit:
	b	begin

printnum:
	push	v1
	push	v2
	set	v1, $e6b0
printnum1:
	ldrl	v2, v1, 0
	maskne	printnum1, v2, 2
printnum2:
	strl	v0, v1, 1
	pop	v2
	pop	v1
	rts

text:
	db	"Hello, World!", 10, 13, 0

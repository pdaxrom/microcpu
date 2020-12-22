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

	macro	nop
	mov	v0, v0
	endm

	macro	set
	setl	#1, #2
	seth	#1, /#2
	endm

	macro	clr
	sub	#1, #1, #1
	endm

	macro	inc
	add	#1, #1, 1
	endm

	macro	dec
	sub	#1, #1, 1
	endm

	macro	push
	str	#1, sp, 0
	sub	sp, sp, 2
	endm

	macro	pop
	add	sp, sp, 2
	ldr	#1, sp, 0
	endm

	macro	bsr
	add	lr, pc, 3
	b	#1
	endm

	macro	rts
	mov	pc, lr
	endm

	macro	jsr
	add	lr, pc, 5
	ldr	pc, pc, 1
	dw	#1
	endm

	macro	jmp
	ldr	pc, pc, 1
	dw	#1
	endm

	macro	beq
	ne	#2, #3
	b	#1
	endm

	macro	bne
	eq	#2, #3
	b	#1
	endm

	macro	blt
	ge	#2, #3		; #2 >= #3
	b	#1		; <
	endm

	macro	ble
	ne	#2, #3		; #2 != #3
	b	#1		; =
	ge	#2, #3		; #2 >= #3
	b	#1		; <
	endm

	macro	bgt
	ge	#2, #3		; #2 >= #3
	b	*+6		; <
	eq	#2, #3		; #2 == #3
	b	#1		; !=
	endm

	macro	bge
	lt	#2, #3		; #2 < #3
	b	#1		; >=
	endm

	macro	bltu
	geu	#2, #3		; #2 >= #3
	b	#1		; <
	endm

	macro	bleu
	ne	#2, #3		; #2 != #3
	b	#1		; =
	geu	#2, #3		; #2 >= #3
	b	#1		; <
	endm

	macro	bgtu
	geu	#2, #3		; #2 >= #3
	b	*+6		; <
	eq	#2, #3		; #2 == #3
	b	#1		; !=
	endm

	macro	bgeu
	ltu	#2, #3		; #2 < #3
	b	#1		; >=
	endm

	macro	bitne
	bts	#2, #3
	b	#1
	endm

	macro	biteq
	btc	#2, #3
	b	#1
	endm

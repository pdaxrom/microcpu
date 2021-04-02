	macro	nop
	mov	v0,v0
	endm

	macro	bsr
	mov	lr, pc
	b	#1
	endm

	macro	rts
	add	pc, lr, 3
	endm

	macro	push
	str	#1, sp, 0
	sub	sp, sp, 2
	endm

	macro	pop
	add	sp, sp, 2
	ldr	#1, sp, 0
	endm

	macro	set
	setl	#1, #2
	seth	#1, /#2
	endm

	macro	clr
	sub	#1, #1, #1
	endm

	macro	jsr
	set	lr, #1
	str	lr, sp, 0
	mov	lr, pc
	ldr	pc, sp, 0
	endm

;
; jmp uses lr
;
	macro	jmp
	set	lr, #1
	mov	pc, lr
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

	macro	maskeq
	mne	#2, #3
	b	#1
	endm

	macro	maskne
	meq	#2, #3
	b	#1
	endm

; Guest memory ABI. All RISC registers are preserved except the load result.
; Native ALU flags are volatile: stores snapshot them in context 18 so ADD/SUB
; can commit their guest flags after the software memory/device dispatcher.
;
; Private scratch: 25=lr, 26=v4, 27=v3, 28=v2, 29=sp, 30=return, 31=mode/result.
; Use an absolute software call: no guest-memory literals, no new RISC opcode,
; and no dependence on the short branch displacement as the uROM grows.
	macro bmask_set
	btc #2, #3
	b #1
	endm

	macro bmask_clear
	bts #2, #3
	b #1
	endm

	macro mcall
	gset pc, 30
	set lr, #1
	mov pc, lr
	endm

	macro readw
	gset lr, 25
	gset v4, 26
	add v4, #2, #3
	mcall memory_read_word
	gget #1, 31
	endm

	macro readb
	gset lr, 25
	gset v4, 26
	add v4, #2, #3
	mcall memory_read_byte
	gget #1, 31
	endm

	macro writew
	gset lr, 25
	gset v3, 27
	gset #1, 31
	getf v3
	gset v3, 18
	gget v3, 27
	gset v4, 26
	add v4, #2, #3
	gget v3, 31
	mcall memory_write_word
	endm

	macro writeb
	gset lr, 25
	gset v3, 27
	gset #1, 31
	getf v3
	gset v3, 18
	gget v3, 27
	gset v4, 26
	add v4, #2, #3
	gget v3, 31
	mcall memory_write_byte
	endm

	macro far_jump
	set lr, #1
	mov pc, lr
	endm

	macro far_call
	set sp, #1
	add lr, pc, 3
	mov pc, sp
	endm

	macro fbeq
	eq #2, #3
	b *+8
	far_jump #1
	endm

	macro fbne
	ne #2, #3
	b *+8
	far_jump #1
	endm

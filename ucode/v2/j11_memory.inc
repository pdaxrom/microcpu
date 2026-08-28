; Guest memory ABI. All RISC registers are preserved except the load result.
; Native ALU flags are volatile: stores snapshot them in context 18 so ADD/SUB
; can commit their guest flags after the software memory/device dispatcher.
;
; Private scratch: 25=lr, 26=v4, 27=v3, 28=v2, 29=sp, 30=return.
; Context 18 holds a read result, or pre-store NZVC plus access mode in bits 6:4.
; CALL/JMP use native absolute microcode targets, never guest-memory literals.
	macro bmask_set
	btc #2, #3
	b #1
	endm

	macro bmask_clear
	bts #2, #3
	b #1
	endm

	macro mcall
	call #1
	endm

	macro readw
	gset lr, 25
	gset v4, 26
	add v4, #2, #3
	mcall memory_read_word
	gget #1, 18
	endm

	macro fetchw
	gset lr, 25
	gset v4, 26
	add v4, #2, #3
	mcall memory_fetch_word
	gget #1, 18
	endm

	macro readb
	gset lr, 25
	gset v4, 26
	add v4, #2, #3
	mcall memory_read_byte
	gget #1, 18
	endm

	macro writew
	gset lr, 25
	gset v3, 27
	gset #1, 28
	getf v3
	gset v3, 18
	gget v3, 27
	gset v4, 26
	add v4, #2, #3
	gget v3, 28
	mcall memory_write_word
	endm

	macro writeb
	gset lr, 25
	gset v3, 27
	gset #1, 28
	getf v3
	gset v3, 18
	gget v3, 27
	gset v4, 26
	add v4, #2, #3
	gget v3, 28
	mcall memory_write_byte
	endm

	macro far_jump
	jmp #1
	endm

	macro far_call
	call #1
	endm

	macro fbeq
	ne #2, #3
	far_jump #1
	endm

	macro fbne
	eq #2, #3
	far_jump #1
	endm

; An explicit write to memory-mapped PSW wins over the instruction's implicit
; condition-code result (including MOV/BIC/BIS/ADD and byte instructions).
; Used only at instruction flag commits; lr is dead at these boundaries.
	macro pset
	gget lr, 14
	bts lr, 8
	gset #1, 8
	endm

; Check an implicit kernel-stack reference, preserving every live RISC reg.
; Use only outside memory helpers: it shares their single scratch frame.
	macro scheck
	gset lr, 25
	gset v2, 28
	gset v3, 27
	mov v2, #1
	mcall stack_check
	endm

	cpu dcj-11
	org 0

	mov #02000, sp

	; Word BIC: N=1, Z=0, V=0, C preserved.
	mov #0177777, r0
	sec
	sev
	bic #0377, r0
	bmi bic_n_ok
	br fail
bic_n_ok
	bne bic_z_ok
	br fail
bic_z_ok
	bvc bic_v_ok
	br fail
bic_v_ok
	bcs bic_zero
	br fail

	; Zero result still preserves C.
bic_zero
	bic #0177400, r0
	beq bic_zero_z_ok
	br fail
bic_zero_z_ok
	bcs bis_word
	br fail

	; Word BIS: set sign, clear V, preserve C.
bis_word
	sev
	bis #0100000, r0
	bmi bis_n_ok
	br fail
bis_n_ok
	bne bis_z_ok
	br fail
bis_z_ok
	bvc bis_v_ok
	br fail
bis_v_ok
	bcs bicb_register
	br fail

	; Byte register destinations preserve their high byte.
bicb_register
	mov #012345, r1
	bicb #0340, r1
	bisb #0200, r1
	bmi bicb_register_n_ok
	br fail
bicb_register_n_ok
	bcs bicb_register_flags_ok
	br fail
bicb_register_flags_ok
	mov r1, result_r1

	; Odd byte address, +1/-1 side effects, and byte stores.
bicb_memory
	mov #byte_target, r2
	bicb #0360, (r2)+
	bisb #0200, -(r2)
	mov r2, result_r2

	; Word memory destinations reuse the same resolver and step by two.
	mov #word_target, r3
	bic #0300, (r3)+
	bis #040000, -(r3)
	mov r3, result_r3

	mov #012345, r0
	halt

fail
	clr r0
	halt

code_end
	ds 01000-code_end
result_r1
	dw 0
result_r2
	dw 0
result_r3
	dw 0
	db 0
byte_target
	db 0377

	even
word_target
	dw 012345

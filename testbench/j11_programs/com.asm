	cpu dcj-11
	org 0

	mov #02000, sp

	; COMB preserves the register high byte and sets byte-width flags.
	mov #012000, r1
	clc
	sev
	comb r1
	bmi comb_n_ok
	br fail
comb_n_ok
	bne comb_z_ok
	br fail
comb_z_ok
	bvc comb_v_ok
	br fail
comb_v_ok
	bcs comb_c_ok
	br fail
comb_c_ok
	cmp #012377, r1
	bne fail

	; A second complement produces zero in the byte without clearing C.
	comb r1
	beq comb_zero_ok
	br fail
comb_zero_ok
	bcs comb_register_ok
	br fail
comb_register_ok
	cmp #012000, r1
	bne fail

	; Word COM uses the same resolver and reports a zero result.
	mov #0177777, r2
	com r2
	beq com_word_z_ok
	br fail
com_word_z_ok
	bcs com_memory
	br fail

	; Byte memory modes retain their one-byte side effects at odd addresses.
com_memory
	mov #byte_target_1, r3
	comb (r3)+
	cmp #byte_target_1+1, r3
	bne fail
	cmpb #0125, byte_target_1
	bne fail

	mov #byte_target_2+1, r4
	comb -(r4)
	cmp #byte_target_2, r4
	bne fail
	cmpb #0170, byte_target_2
	bne fail

	; Word memory autoincrement remains a two-byte operation.
	mov #word_target, r5
	com (r5)+
	cmp #word_target+2, r5
	bne fail
	cmp #0165432, word_target
	bne fail

	mov #012345, r0
	halt

fail
	clr r0
	halt

	org 01000
	db 0
byte_target_1
	db 0252
	db 0
byte_target_2
	db 0207

	even
word_target
	dw 012345

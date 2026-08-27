	cpu dcj-11
	org 0

	mov #02000, sp

	; Word-register boundaries and carry preservation.
	mov #077777, r1
	sec
	inc r1
	bmi inc_word_n_ok
	jmp fail
inc_word_n_ok
	bvs inc_word_v_ok
	jmp fail
inc_word_v_ok
	bcs inc_word_c_ok
	jmp fail
inc_word_c_ok
	cmp #0100000, r1
	bne register_failure

	mov #0100000, r1
	clc
	dec r1
	bpl dec_word_n_ok
	jmp fail
dec_word_n_ok
	bvs dec_word_v_ok
	jmp fail
dec_word_v_ok
	bcc dec_word_c_ok
	jmp fail
dec_word_c_ok
	cmp #077777, r1
	bne register_failure

	mov #0177777, r1
	sec
	inc r1
	beq inc_word_z_ok
	jmp fail
inc_word_z_ok
	bvc inc_word_z_v_ok
	jmp fail
inc_word_z_v_ok
	bcs inc_word_z_c_ok
	jmp fail
inc_word_z_c_ok

	mov #1, r1
	clc
	dec r1
	beq dec_word_z_ok
	jmp fail
dec_word_z_ok
	bvc dec_word_z_v_ok
	jmp fail
dec_word_z_v_ok
	bcc byte_register_tests
	jmp fail

byte_register_tests
	; Byte-register operations retain the high byte and use bit 7 for N/V.
	mov #012177, r2
	sec
	incb r2
	bmi inc_byte_n_ok
	jmp fail
inc_byte_n_ok
	bvs inc_byte_v_ok
	jmp fail
inc_byte_v_ok
	bcs inc_byte_c_ok
	jmp fail
inc_byte_c_ok
	cmp #012200, r2
	bne register_failure

	mov #012200, r2
	clc
	decb r2
	bpl dec_byte_n_ok
	jmp fail
dec_byte_n_ok
	bvs dec_byte_v_ok
	jmp fail
dec_byte_v_ok
	bcc dec_byte_c_ok
	jmp fail
dec_byte_c_ok
	cmp #012177, r2
	bne register_failure

	mov #012377, r2
	sec
	incb r2
	beq inc_byte_z_ok
	jmp fail
inc_byte_z_ok
	bvc inc_byte_z_v_ok
	jmp fail
inc_byte_z_v_ok
	bcs inc_byte_z_c_ok
	jmp fail
inc_byte_z_c_ok
	cmp #012000, r2
	bne register_failure

	mov #012001, r2
	clc
	decb r2
	beq dec_byte_z_ok
	jmp fail
dec_byte_z_ok
	bvc dec_byte_z_v_ok
	jmp fail
dec_byte_z_v_ok
	bcc addressing_tests
	jmp fail

register_failure
	jmp fail

addressing_tests
	; Exercise every memory EA mode, including byte/word side effects.
	mov #mode1_target, r3
	inc (r3)
	cmp #2, mode1_target
	bne addressing_failure

	mov #mode2_target, r3
	clc
	incb (r3)+
	beq mode2_z_ok
	jmp fail
mode2_z_ok
	bcc mode2_c_ok
	jmp fail
mode2_c_ok
	cmp #mode2_target+1, r3
	bne addressing_failure
	cmpb #0, mode2_target
	bne addressing_failure
	cmpb #0125, mode2_target+1
	bne addressing_failure

	mov #mode3_pointer, r3
	inc @(r3)+
	cmp #mode3_pointer+2, r3
	bne addressing_failure
	cmp #4, mode3_target
	bne addressing_failure

	mov #mode4_target+2, r4
	dec -(r4)
	cmp #mode4_target, r4
	bne addressing_failure
	cmp #4, mode4_target
	bne addressing_failure

	mov #mode5_pointer+2, r4
	dec @-(r4)
	cmp #mode5_pointer, r4
	bne addressing_failure
	cmp #5, mode5_target
	bne addressing_failure

	mov #mode6_target-4, r5
	inc 4(r5)
	cmp #7, mode6_target
	bne addressing_failure

	mov #mode7_pointer-6, r5
	dec @6(r5)
	cmp #7, mode7_target
	bne addressing_failure

	; PC-relative modes use the same shared resolver.
	inc pc_relative_target
	cmp #011, pc_relative_target
	bne addressing_failure
	dec @pc_relative_pointer
	cmp #011, pc_relative_deferred_target
	bne addressing_failure

	mov #012345, r0
	halt

addressing_failure
	jmp fail

fail
	clr r0
	halt

	org 01000
mode1_target
	dw 1
mode2_target
	db 0377, 0125
	even
mode3_pointer
	dw mode3_target
mode3_target
	dw 3
mode4_target
	dw 5
mode5_pointer
	dw mode5_target
mode5_target
	dw 6
mode6_target
	dw 6
mode7_pointer
	dw mode7_target
mode7_target
	dw 010
pc_relative_target
	dw 010
pc_relative_pointer
	dw pc_relative_deferred_target
pc_relative_deferred_target
	dw 012

	cpu dcj-11
	org 0

	mov #02000, sp

	; ROR: old C enters the sign bit, bit 0 becomes C, V=N xor C.
	mov #1, r1
	clc
	ror r1
	beq ror_zero_z_ok
	jmp fail
ror_zero_z_ok
	bpl ror_zero_n_ok
	jmp fail
ror_zero_n_ok
	bvs ror_zero_v_ok
	jmp fail
ror_zero_v_ok
	bcs ror_zero_c_ok
	jmp fail
ror_zero_c_ok
	cmp #0, r1
	beq ror_sign_test
	jmp fail

ror_sign_test
	mov #1, r1
	sec
	ror r1
	bmi ror_sign_n_ok
	jmp fail
ror_sign_n_ok
	bvc ror_sign_v_ok
	jmp fail
ror_sign_v_ok
	bcs ror_sign_c_ok
	jmp fail
ror_sign_c_ok
	cmp #0100000, r1
	beq rol_word_test
	jmp fail

	; ROL: old C enters bit 0 and the old sign becomes C.
rol_word_test
	mov #0100000, r1
	sec
	rol r1
	bpl rol_n_ok
	jmp fail
rol_n_ok
	bne rol_z_ok
	jmp fail
rol_z_ok
	bvs rol_v_ok
	jmp fail
rol_v_ok
	bcs rol_c_ok
	jmp fail
rol_c_ok
	cmp #1, r1
	beq asr_positive_test
	jmp fail

	; ASR retains the old sign and shifts bit 0 into C.
asr_positive_test
	mov #1, r1
	clc
	asr r1
	beq asr_zero_z_ok
	jmp fail
asr_zero_z_ok
	bpl asr_zero_n_ok
	jmp fail
asr_zero_n_ok
	bvs asr_zero_v_ok
	jmp fail
asr_zero_v_ok
	bcs asr_zero_c_ok
	jmp fail
asr_zero_c_ok

	mov #0100000, r1
	asr r1
	bmi asr_sign_n_ok
	jmp fail
asr_sign_n_ok
	bne asr_sign_z_ok
	jmp fail
asr_sign_z_ok
	bvs asr_sign_v_ok
	jmp fail
asr_sign_v_ok
	bcc asr_sign_c_ok
	jmp fail
asr_sign_c_ok
	cmp #0140000, r1
	beq asl_carry_test
	jmp fail

	; ASL shifts the old sign into C.
asl_carry_test
	mov #0100000, r1
	clc
	asl r1
	beq asl_zero_z_ok
	jmp fail
asl_zero_z_ok
	bpl asl_zero_n_ok
	jmp fail
asl_zero_n_ok
	bvs asl_zero_v_ok
	jmp fail
asl_zero_v_ok
	bcs asl_zero_c_ok
	jmp fail
asl_zero_c_ok

	mov #040000, r1
	asl r1
	bmi asl_sign_n_ok
	jmp fail
asl_sign_n_ok
	bne asl_sign_z_ok
	jmp fail
asl_sign_z_ok
	bvs asl_sign_v_ok
	jmp fail
asl_sign_v_ok
	bcc asl_sign_c_ok
	jmp fail
asl_sign_c_ok
	cmp #0100000, r1
	beq byte_tests
	jmp fail

byte_tests
	; Byte forms preserve bits 15:8 of a register.
	mov #012001, r2
	sec
	rorb r2
	bmi rorb_n_ok
	jmp fail
rorb_n_ok
	bvc rorb_v_ok
	jmp fail
rorb_v_ok
	bcs rorb_c_ok
	jmp fail
rorb_c_ok
	cmp #012200, r2
	beq rolb_test
	jmp fail

rolb_test
	mov #012200, r2
	sec
	rolb r2
	bpl rolb_n_ok
	jmp fail
rolb_n_ok
	bne rolb_z_ok
	jmp fail
rolb_z_ok
	bvs rolb_v_ok
	jmp fail
rolb_v_ok
	bcs rolb_c_ok
	jmp fail
rolb_c_ok
	cmp #012001, r2
	beq asrb_zero_test
	jmp fail

asrb_zero_test
	mov #012001, r2
	clc
	asrb r2
	beq asrb_zero_z_ok
	jmp fail
asrb_zero_z_ok
	bvs asrb_zero_v_ok
	jmp fail
asrb_zero_v_ok
	bcs asrb_zero_c_ok
	jmp fail
asrb_zero_c_ok
	cmp #012000, r2
	beq asrb_sign_test
	jmp fail

asrb_sign_test
	mov #012200, r2
	asrb r2
	bmi asrb_sign_n_ok
	jmp fail
asrb_sign_n_ok
	bvs asrb_sign_v_ok
	jmp fail
asrb_sign_v_ok
	bcc asrb_sign_c_ok
	jmp fail
asrb_sign_c_ok
	cmp #012300, r2
	beq aslb_carry_test
	jmp fail

aslb_carry_test
	mov #012200, r2
	aslb r2
	beq aslb_zero_z_ok
	jmp fail
aslb_zero_z_ok
	bvs aslb_zero_v_ok
	jmp fail
aslb_zero_v_ok
	bcs aslb_zero_c_ok
	jmp fail
aslb_zero_c_ok
	cmp #012000, r2
	beq aslb_sign_test
	jmp fail

aslb_sign_test
	mov #012100, r2
	aslb r2
	bmi aslb_sign_n_ok
	jmp fail
aslb_sign_n_ok
	bvs aslb_sign_v_ok
	jmp fail
aslb_sign_v_ok
	bcc aslb_sign_c_ok
	jmp fail
aslb_sign_c_ok
	cmp #012200, r2
	beq memory_tests
	jmp fail

memory_tests
	clc
	ror @#ror_target
	cmp #0, ror_target
	beq rolb_memory_test
	jmp fail

rolb_memory_test
	mov #rolb_target, r3
	sec
	rolb (r3)+
	cmp #rolb_target+1, r3
	beq rolb_memory_pointer_ok
	jmp fail
rolb_memory_pointer_ok
	cmpb #1, rolb_target
	beq rolb_memory_neighbor
	jmp fail
rolb_memory_neighbor
	cmpb #0125, rolb_target+1
	beq asr_memory_test
	jmp fail

asr_memory_test
	mov #asr_target+2, r4
	asr -(r4)
	cmp #asr_target, r4
	beq asr_memory_pointer_ok
	jmp fail
asr_memory_pointer_ok
	cmp #0, asr_target
	beq asl_memory_test
	jmp fail

asl_memory_test
	asl @#asl_target
	cmp #0, asl_target
	beq success
	jmp fail

success
	mov #012345, r0
	halt

fail
	clr r0
	halt

	org 03000
ror_target
	dw 1
rolb_target
	db 0200, 0125
	even
asr_target
	dw 1
asl_target
	dw 0100000

	cpu dcj-11
	org 0

	mov #02000, sp

	; NEG replaces every NZVC flag.
	mov #0, r1
	scc
	neg r1
	beq neg_zero_z_ok
	jmp fail
neg_zero_z_ok
	bpl neg_zero_n_ok
	jmp fail
neg_zero_n_ok
	bvc neg_zero_v_ok
	jmp fail
neg_zero_v_ok
	bcc neg_zero_c_ok
	jmp fail
neg_zero_c_ok

	mov #1, r1
	neg r1
	bmi neg_one_n_ok
	jmp fail
neg_one_n_ok
	bne neg_one_z_ok
	jmp fail
neg_one_z_ok
	bvc neg_one_v_ok
	jmp fail
neg_one_v_ok
	bcs neg_one_c_ok
	jmp fail
neg_one_c_ok
	cmp #0177777, r1
	beq neg_min_test
	jmp fail

neg_min_test
	mov #0100000, r1
	neg r1
	bmi neg_min_n_ok
	jmp fail
neg_min_n_ok
	bvs neg_min_v_ok
	jmp fail
neg_min_v_ok
	bcs neg_min_c_ok
	jmp fail
neg_min_c_ok
	cmp #0100000, r1
	beq neg_byte_test
	jmp fail

neg_byte_test
	mov #012200, r2
	negb r2
	bmi negb_n_ok
	jmp fail
negb_n_ok
	bvs negb_v_ok
	jmp fail
negb_v_ok
	bcs negb_c_ok
	jmp fail
negb_c_ok
	cmp #012200, r2		; high byte is retained
	beq adc_word_no_carry
	jmp fail

adc_word_no_carry
	mov #0100000, r1
	clc
	sev
	adc r1
	bmi adc_no_c_n_ok
	jmp fail
adc_no_c_n_ok
	bvc adc_no_c_v_ok
	jmp fail
adc_no_c_v_ok
	bcc adc_no_c_c_ok
	jmp fail
adc_no_c_c_ok
	cmp #0100000, r1
	beq adc_word_wrap
	jmp fail

adc_word_wrap
	mov #0177777, r1
	sec
	adc r1
	beq adc_wrap_z_ok
	jmp fail
adc_wrap_z_ok
	bvc adc_wrap_v_ok
	jmp fail
adc_wrap_v_ok
	bcs adc_wrap_c_ok
	jmp fail
adc_wrap_c_ok
	cmp #0, r1
	beq adc_word_overflow
	jmp fail

adc_word_overflow
	mov #077777, r1
	sec
	adc r1
	bmi adc_overflow_n_ok
	jmp fail
adc_overflow_n_ok
	bvs adc_overflow_v_ok
	jmp fail
adc_overflow_v_ok
	bcc adc_overflow_c_ok
	jmp fail
adc_overflow_c_ok
	cmp #0100000, r1
	beq adc_byte_wrap
	jmp fail

adc_byte_wrap
	mov #012377, r2
	sec
	adcb r2
	beq adcb_wrap_z_ok
	jmp fail
adcb_wrap_z_ok
	bvc adcb_wrap_v_ok
	jmp fail
adcb_wrap_v_ok
	bcs adcb_wrap_c_ok
	jmp fail
adcb_wrap_c_ok
	cmp #012000, r2
	beq adc_byte_overflow
	jmp fail

adc_byte_overflow
	mov #012177, r2
	sec
	adcb r2
	bmi adcb_overflow_n_ok
	jmp fail
adcb_overflow_n_ok
	bvs adcb_overflow_v_ok
	jmp fail
adcb_overflow_v_ok
	bcc adcb_overflow_c_ok
	jmp fail
adcb_overflow_c_ok
	cmp #012200, r2
	beq sbc_word_no_carry
	jmp fail

sbc_word_no_carry
	mov #0100000, r1
	clc
	sev
	sbc r1
	bmi sbc_no_c_n_ok
	jmp fail
sbc_no_c_n_ok
	bvc sbc_no_c_v_ok
	jmp fail
sbc_no_c_v_ok
	bcc sbc_no_c_c_ok
	jmp fail
sbc_no_c_c_ok
	cmp #0100000, r1
	beq sbc_word_wrap
	jmp fail

sbc_word_wrap
	mov #0, r1
	sec
	sbc r1
	bmi sbc_wrap_n_ok
	jmp fail
sbc_wrap_n_ok
	bne sbc_wrap_z_ok
	jmp fail
sbc_wrap_z_ok
	bvc sbc_wrap_v_ok
	jmp fail
sbc_wrap_v_ok
	bcs sbc_wrap_c_ok
	jmp fail
sbc_wrap_c_ok
	cmp #0177777, r1
	beq sbc_word_overflow
	jmp fail

sbc_word_overflow
	mov #0100000, r1
	sec
	sbc r1
	bpl sbc_overflow_n_ok
	jmp fail
sbc_overflow_n_ok
	bvs sbc_overflow_v_ok
	jmp fail
sbc_overflow_v_ok
	bcc sbc_overflow_c_ok
	jmp fail
sbc_overflow_c_ok
	cmp #077777, r1
	beq sbc_byte_wrap
	jmp fail

sbc_byte_wrap
	mov #012000, r2
	sec
	sbcb r2
	bmi sbcb_wrap_n_ok
	jmp fail
sbcb_wrap_n_ok
	bne sbcb_wrap_z_ok
	jmp fail
sbcb_wrap_z_ok
	bvc sbcb_wrap_v_ok
	jmp fail
sbcb_wrap_v_ok
	bcs sbcb_wrap_c_ok
	jmp fail
sbcb_wrap_c_ok
	cmp #012377, r2
	beq sbc_byte_overflow
	jmp fail

sbc_byte_overflow
	mov #012200, r2
	sec
	sbcb r2
	bpl sbcb_overflow_n_ok
	jmp fail
sbcb_overflow_n_ok
	bvs sbcb_overflow_v_ok
	jmp fail
sbcb_overflow_v_ok
	bcc sbcb_overflow_c_ok
	jmp fail
sbcb_overflow_c_ok
	cmp #012177, r2
	beq memory_tests
	jmp fail

memory_tests
	neg @#neg_target
	cmp #0177777, neg_target
	beq adc_memory_test
	jmp fail

adc_memory_test
	mov #adc_byte_target, r3
	sec
	adcb (r3)+
	beq adc_memory_z_ok
	jmp fail
adc_memory_z_ok
	bcs adc_memory_c_ok
	jmp fail
adc_memory_c_ok
	cmp #adc_byte_target+1, r3
	beq adc_memory_pointer_ok
	jmp fail
adc_memory_pointer_ok
	cmpb #0, adc_byte_target
	beq adc_memory_neighbor
	jmp fail
adc_memory_neighbor
	cmpb #0125, adc_byte_target+1
	beq sbc_memory_test
	jmp fail

sbc_memory_test
	mov #sbc_target+2, r4
	sec
	sbc -(r4)
	cmp #sbc_target, r4
	beq sbc_memory_pointer_ok
	jmp fail
sbc_memory_pointer_ok
	cmp #0177777, sbc_target
	beq success
	jmp fail

success
	mov #012345, r0
	halt

fail
	clr r0
	halt

	org 01000
neg_target
	dw 1
adc_byte_target
	db 0377, 0125
	even
sbc_target
	dw 0

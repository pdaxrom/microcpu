	cpu dcj-11
	org 0

start
	mov #02000, sp

	cmp #1, #2
	bmi cmp_borrow_n_ok
	br fail
cmp_borrow_n_ok
	bne cmp_borrow_z_ok
	br fail
cmp_borrow_z_ok
	bvc cmp_borrow_v_ok
	br fail
cmp_borrow_v_ok
	bcs cmp_borrow_c_ok
	br fail
cmp_borrow_c_ok

	cmp #0100000, #1
	bpl cmp_overflow_n_ok
	br fail
cmp_overflow_n_ok
	bne cmp_overflow_z_ok
	br fail
cmp_overflow_z_ok
	bvs cmp_overflow_v_ok
	br fail
cmp_overflow_v_ok
	bcc cmp_overflow_c_ok
	br fail
cmp_overflow_c_ok

	cmpb #0, #1
	bmi cmpb_borrow_n_ok
	br fail
cmpb_borrow_n_ok
	bcs cmpb_borrow_c_ok
	br fail
cmpb_borrow_c_ok

	cmpb #0200, #1
	bpl cmpb_overflow_n_ok
	br fail
cmpb_overflow_n_ok
	bvs cmpb_overflow_v_ok
	br fail
cmpb_overflow_v_ok
	bcc bit_zero
	br fail

bit_zero
	sec
	sev
	bit #1, #2
	beq bit_zero_z_ok
	br fail
bit_zero_z_ok
	bpl bit_zero_n_ok
	br fail
bit_zero_n_ok
	bvc bit_zero_v_ok
	br fail
bit_zero_v_ok
	bcs bitb_negative
	br fail

bitb_negative
	bitb #0200, #0377
	bmi bitb_n_ok
	br fail
bitb_n_ok
	bne bitb_z_ok
	br fail
bitb_z_ok
	bvc bitb_v_ok
	br fail
bitb_v_ok
	bcs add_overflow
	br fail

add_overflow
	mov #077777, r0
	add #1, r0
	bmi add_overflow_n_ok
	br fail
add_overflow_n_ok
	bne add_overflow_z_ok
	br fail
add_overflow_z_ok
	bvs add_overflow_v_ok
	br fail
add_overflow_v_ok
	bcc add_carry
	br fail

add_carry
	mov #0177777, r1
	add #1, r1
	beq add_carry_z_ok
	br fail
add_carry_z_ok
	bvc add_carry_v_ok
	br fail
add_carry_v_ok
	bcs add_memory
	br fail

add_memory
	mov r1, result_add_carry
	mov #target_add, r2
	add #1, (r2)+
	mov r2, result_add_r2

sub_borrow
	mov #0, r0
	sub #1, r0
	bmi sub_borrow_n_ok
	br fail
sub_borrow_n_ok
	bne sub_borrow_z_ok
	br fail
sub_borrow_z_ok
	bvc sub_borrow_v_ok
	br fail
sub_borrow_v_ok
	bcs sub_overflow
	br fail

sub_overflow
	mov #0100000, r0
	sub #1, r0
	bpl sub_overflow_n_ok
	br fail
sub_overflow_n_ok
	bne sub_overflow_z_ok
	br fail
sub_overflow_z_ok
	bvs sub_overflow_v_ok
	br fail
sub_overflow_v_ok
	bcc sub_memory
	br fail

sub_memory
	mov #target_sub, r3
	sub #1, (r3)+
	mov r3, result_sub_r3

	; Leave the signed-overflow result and flags visible at HALT.
	mov #077777, r0
	add #1, r0
	halt

fail
	dw 0xffff

code_end
	ds 01000-code_end
result_add_carry
	dw 0177777
result_add_r2
	dw 0
result_sub_r3
	dw 0

result_end
	ds 01200-result_end
target_add
	dw 012345
target_sub
	dw 07654

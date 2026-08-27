	cpu dcj-11
	org 0

	br start

	org 010
	dw reserved_handler
	dw 0

	org 020
reserved_handler
	inc r4
	rti

start
	mov #02000, sp
	clr r4

	; With N clear, SXT writes zero, sets Z, clears V, and preserves C.
	mov #012345, r1
	cln
	sec
	sev
	sxt r1
	beq zero_z_ok
	br fail
zero_z_ok
	bpl zero_n_ok
	br fail
zero_n_ok
	bvc zero_v_ok
	br fail
zero_v_ok
	bcs zero_c_ok
	br fail
zero_c_ok
	cmp #0, r1
	bne fail

	; With N set, SXT writes all ones and preserves a clear carry.
	mov #012345, r1
	sen
	clc
	sev
	sxt r1
	bmi negative_n_ok
	br fail
negative_n_ok
	bne negative_z_ok
	br fail
negative_z_ok
	bvc negative_v_ok
	br fail
negative_v_ok
	bcc negative_c_ok
	br fail
negative_c_ok
	cmp #0177777, r1
	bne fail

	; The destination uses the normal word EA side effects.
	mov #word_target+2, r2
	sen
	sec
	sxt -(r2)
	bmi memory_n_ok
	br fail
memory_n_ok
	bcs memory_c_ok
	br fail
memory_c_ok
	cmp #word_target, r2
	bne fail
	cmp #0177777, word_target
	bne fail

	mov #012345, r0
	halt

fail
	clr r0
	halt

	org 01000
word_target
	dw 012345

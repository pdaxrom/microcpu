	cpu dcj-11
	org 0

start
	mov #02000, sp

	; Register destination: XOR sets N/Z, clears V, and preserves C.
	mov #0177400, r1
	mov #000377, r2
	sec
	sev
	xor r1, r2
	bmi xor_register_n_ok
	br fail
xor_register_n_ok
	bne xor_register_z_ok
	br fail
xor_register_z_ok
	bvc xor_register_v_ok
	br fail
xor_register_v_ok
	bcs xor_register_c_ok
	br fail
xor_register_c_ok
	cmp #0177777, r2
	bne fail

	; The destination uses the shared word EA resolver and writes memory.
	mov #word_target, r3
	mov #000777, r1
	clc
	sev
	xor r1, (r3)+
	bmi xor_memory_n_ok
	br fail
xor_memory_n_ok
	bne xor_memory_z_ok
	br fail
xor_memory_z_ok
	bvc xor_memory_v_ok
	br fail
xor_memory_v_ok
	bcc xor_memory_c_ok
	br fail
xor_memory_c_ok
	cmp #word_target+2, r3
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
	dw 0177000

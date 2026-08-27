	cpu dcj-11
	org 0

start
	scc
	mov #0177777, r0
	clrb r0
	beq clear_byte_register_z_ok
	br fail
clear_byte_register_z_ok
	bcc clear_byte_register_c_ok
	br fail
clear_byte_register_c_ok
	bpl clear_byte_register_n_ok
	br fail
clear_byte_register_n_ok
	bvc clear_byte_register_flags_ok
	br fail
clear_byte_register_flags_ok
	mov r0, result_clear_byte_register

	clr @#target_clear_word
	beq clear_word_z_ok
	br fail
clear_word_z_ok
	bcc clear_word_c_ok
	br fail
clear_word_c_ok

	clrb @#target_clear_byte+1
	beq clear_byte_memory_z_ok
	br fail
clear_byte_memory_z_ok
	bcc test_zero
	br fail

test_zero
	tst #0
	beq test_zero_z_ok
	br fail
test_zero_z_ok
	bcc test_zero_c_ok
	br fail
test_zero_c_ok
	bvc test_zero_v_ok
	br fail
test_zero_v_ok
	bpl test_memory_byte
	br fail

test_memory_byte
	mov #source_test_byte, r1
	tstb (r1)+
	bmi test_byte_n_ok
	br fail
test_byte_n_ok
	bne test_byte_z_ok
	br fail
test_byte_z_ok
	bcc test_byte_c_ok
	br fail
test_byte_c_ok
	mov r1, result_test_byte_r1

	; Leave TSTB flags observable at HALT: N=1, Z=V=C=0.
	tstb #0200
	halt

fail
	dw 0xffff

code_end
	ds 01000-code_end
result_clear_byte_register
	dw 0
result_test_byte_r1
	dw 0
target_clear_word
	dw 012345
target_clear_byte
	dw 012345

result_end
	ds 01200-result_end
source_test_byte
	db 0200, 0

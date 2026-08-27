	cpu dcj-11
	org 0

	mov #02000, sp

	; Register result 012345 -> 162424.  Its low byte is positive/nonzero,
	; and SWAB clears V/C even when all condition codes start set.
	scc
	mov #012345, r1
	swab r1
	bpl register_n_ok
	br fail
register_n_ok
	bne register_z_ok
	br fail
register_z_ok
	bvc register_v_ok
	br fail
register_v_ok
	bcc register_c_ok
	br fail
register_c_ok
	cmp #0162424, r1
	bne fail

	; Zero is determined from the low byte of the swapped result, not the
	; complete word: 000377 -> 177400 has a zero low byte.
	scc
	mov #000377, r1
	swab r1
	beq zero_z_ok
	br fail
zero_z_ok
	bpl zero_n_ok
	br fail
zero_n_ok
	bvc zero_v_ok
	br fail
zero_v_ok
	bcc zero_c_ok
	br fail
zero_c_ok
	cmp #0177400, r1
	bne fail

	; Bit 7 of the result low byte supplies N: 100000 -> 000200.
	scc
	mov #0100000, r1
	swab r1
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
	cmp #000200, r1
	bne fail

	; SWAB is a word RMW operation and therefore increments a general
	; autoincrement register by two.
	mov #word_target, r2
	swab (r2)+
	cmp #word_target+2, r2
	bne fail
	cmp #0162424, word_target
	bne fail

	mov #012345, r0
	halt

fail
	clr r0
	halt

	org 01000
word_target
	dw 012345

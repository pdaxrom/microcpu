	cpu dcj-11
	org 0

	mov #02000, sp
	mov #3, r1
	clr r2

loop
	add #1, r2
	scc
	sob r1, loop

	; SOB changes neither NZVC nor any register except its counter and PC.
	bmi sob_n_ok
	br fail
sob_n_ok
	beq sob_z_ok
	br fail
sob_z_ok
	bvs sob_v_ok
	br fail
sob_v_ok
	bcs sob_c_ok
	br fail
sob_c_ok
	cmp #0, r1
	bne fail
	cmp #3, r2
	bne fail
	cmp #02000, sp
	bne fail

	mov #012345, r0
	halt

fail
	clr r0
	halt

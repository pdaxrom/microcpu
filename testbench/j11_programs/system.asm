	cpu dcj-11
	org 0

	br start

	org 060
	dw irq_handler
	dw 0200			; BR4 while the handler is active

	org 0100
irq_handler
	inc r1
	rti

	org 0200
start
	mov #02000, sp

	; MFPT returns the DCJ11 processor type in R0 and leaves NZVC unchanged.
	sen
	clz
	sev
	sec
	mfpt
	bmi mfpt_n_ok
	br fail
mfpt_n_ok
	bne mfpt_z_ok
	br fail
mfpt_z_ok
	bvs mfpt_v_ok
	br fail
mfpt_v_ok
	bcs mfpt_c_ok
	br fail
mfpt_c_ok
	cmp #5, r0
	bne fail

	; SPL replaces only PSW priority and preserves the condition codes.
	sen
	clz
	sev
	sec
	spl 5
	bmi spl5_n_ok
	br fail
spl5_n_ok
	bne spl5_z_ok
	br fail
spl5_z_ok
	bvs spl5_v_ok
	br fail
spl5_v_ok
	bcs spl5_c_ok
	br fail
spl5_c_ok
	mfps r2
	cmp #0177653, r2		; priority 5 plus N/V/C
	bne fail

	cln
	sez
	clv
	clc
	spl 2
	beq spl2_z_ok
	br fail
spl2_z_ok
	bpl spl2_n_ok
	br fail
spl2_n_ok
	bvc spl2_v_ok
	br fail
spl2_v_ok
	bcc spl2_c_ok
	br fail
spl2_c_ok
	mfps r3
	cmp #0104, r3		; priority 2 plus Z
	bne fail

	; The testbench verifies that execution stops here until it supplies BR4.
	spl 0
	clr r1
	mov #1, r0
	wait
	mov #012345, r0
	halt

fail
	clr r0
	halt

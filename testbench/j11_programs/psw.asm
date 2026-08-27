	cpu dcj-11
	org 0

start
	; Seed H and T through RTI.  MTPS must preserve both bits.
	mov #return_frame, sp
	rti

after_rti
	mtps #0
	mfps r5
	cmp #020, r5
	bne fail

	; Register MFPS sign-extends bit 7 and updates NZV while preserving C.
	mov #0357, r1
	mtps r1
	mfps r2
	bmi mfps_register_n_ok
	br fail
mfps_register_n_ok
	bne mfps_register_z_ok
	br fail
mfps_register_z_ok
	bvc mfps_register_v_ok
	br fail
mfps_register_v_ok
	bcs mfps_register_c_ok
	br fail
mfps_register_c_ok
	cmp #0177777, r2		; 0357 plus preserved T becomes 0377
	bne fail

	; A memory destination stores one byte and advances R3 by one.
	mtps #0201
	mov #byte_target, r3
	mfps (r3)+
	cmp #byte_target+1, r3
	bne fail
	cmpb #0221, byte_target	; source priority/C plus preserved T
	bne fail
	cmpb #0125, byte_target+1
	bne fail

	; MTPS uses byte source side effects and ignores source bit 4.
	mov #psw_source, r3
	mtps (r3)+
	mfps r4
	cmp #psw_source+1, r3
	bne fail
	cmp #0177761, r4		; 0341 with preserved T becomes 0361
	bne fail

	mov #012345, r0
	halt

fail
	clr r0
	halt

	align 2
return_frame
	dw after_rti
	dw 0420			; H and T

	org 01000
byte_target
	db 0
	db 0125
psw_source
	db 0341

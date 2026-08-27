	cpu dcj-11
	org 0

	br start

	org 014
	dw bpt_handler
	dw 0
	dw iot_handler
	dw 0

	org 030
	dw emt_handler
	dw 0
	dw trap_handler
	dw 0

	org 040
start
	mov #02000, sp
	clr r0
	scc

	bpt
after_bpt
	iot
after_iot
	emt 0123
after_emt
	trap 0256
after_trap

	; Every RTI must restore the pre-trap flags and stack pointer.
	bmi trap_n_ok
	br fail
trap_n_ok
	beq trap_z_ok
	br fail
trap_z_ok
	bvs trap_v_ok
	br fail
trap_v_ok
	bcs trap_c_ok
	br fail
trap_c_ok
	cmp #017, r0
	bne fail
	cmp #02000, sp
	bne fail

	mov #012345, r0
	halt

fail
	clr r0
	halt

bpt_handler
	bis #1, r0
	rti

iot_handler
	bis #2, r0
	rti

emt_handler
	bis #4, r0
	rti

trap_handler
	bis #010, r0
	rti

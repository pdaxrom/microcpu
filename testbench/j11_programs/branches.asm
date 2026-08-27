	cpu dcj-11
	org 0

start
	ccc
	bne z_clear_ok
	br fail
z_clear_ok
	beq fail
	sez
	beq z_set_ok
	br fail
z_set_ok
	bne fail

	ccc
	bge ge_ok
	br fail
ge_ok
	blt fail
	sen
	blt lt_ok
	br fail
lt_ok
	bge fail

	ccc
	bgt gt_ok
	br fail
gt_ok
	ble fail
	sez
	ble le_z_ok
	br fail
le_z_ok
	bgt fail
	ccc
	sen
	ble le_nv_ok
	br fail
le_nv_ok

	ccc
	bpl pl_ok
	br fail
pl_ok
	bmi fail
	sen
	bmi mi_ok
	br fail
mi_ok
	bpl fail

	ccc
	bhi hi_ok
	br fail
hi_ok
	blos fail
	sec
	blos los_ok
	br fail
los_ok
	bhi fail

	ccc
	bvc vc_ok
	br fail
vc_ok
	bvs fail
	sev
	bvs vs_ok
	br fail
vs_ok
	bvc fail

	ccc
	bcc cc_ok
	br fail
cc_ok
	bcs fail
	sec
	bcs success
	br fail

success
	halt

fail
	dw 0xffff

include ../../asm/include/pseudo.inc
include ../include/test.inc

org $0000

	b branch_start
	setl v4, 1
	b fail

branch_start:
	set v0, 0
	set v1, 3
loop:
	add v0, v0, 1
	lt v0, v1
	b loop_done
	b loop
loop_done:
	check_eq16 v0, 3, 2

	set v0, 5
	set v1, 5
	setl v4, 3
	eq v0, v1
	b fail

	setl v4, 4
	ne v0, v1
	b ne_not_taken_ok
	b fail
ne_not_taken_ok:

	set v1, 6
	setl v4, 5
	ne v0, v1
	b fail

	set v0, 1
	set v1, 2
	setl v4, 6
	mi v0, v1
	b fail

	setl v4, 7
	mi v1, v0
	b mi_not_taken_ok
	b fail
mi_not_taken_ok:

	set v0, $8000
	set v1, 1
	setl v4, 8
	vs v0, v1
	b fail

	set v0, 1
	set v1, 1
	setl v4, 9
	vs v0, v1
	b vs_not_taken_ok
	b fail
vs_not_taken_ok:

	set v0, $ffff
	set v1, 1
	setl v4, 10
	lt v0, v1
	b fail

	setl v4, 11
	ge v0, v1
	b ge_not_taken_ok
	b fail
ge_not_taken_ok:

	setl v4, 12
	geu v0, v1
	b fail

	setl v4, 13
	ltu v0, v1
	b ltu_not_taken_ok
	b fail
ltu_not_taken_ok:

	set v0, 1
	set v1, $ffff
	setl v4, 14
	ltu v0, v1
	b fail

	setl v4, 15
	geu v0, v1
	b geu_not_taken_ok
	b fail
geu_not_taken_ok:

	set v0, %0101
	set v1, %0010
	setl v4, 16
	btc v0, v1
	b fail

	setl v4, 17
	bts v0, v1
	b bts_not_taken_ok
	b fail
bts_not_taken_ok:

	set v1, %0001
	setl v4, 18
	bts v0, v1
	b fail

	setl v4, 19
	btc v0, v1
	b btc_not_taken_ok
	b fail
btc_not_taken_ok:

	set v0, pc_target
	mov pc, v0
	setl v4, 20
	b fail

pc_target:
	test_pass

fail:
	setl v3, TEST_STATUS
	seth v3, /TEST_STATUS
	strl v4, v3, 0
	b *

include ../../asm/include/pseudo.inc
include ../include/test.inc

org $0000

	set v0, 1
	add v1, v0, 15
	check_eq16 v1, 16, 1

	add v1, v0, 16
	check_eq16 v1, 1, 2

	shl v1, v0, 15
	check_eq16 v1, $8000, 3

	shl v1, v0, 16
	check_eq16 v1, 1, 4

	set v0, 0
	setl v4, 5
	eq v0, 16
	b fail

	set v0, 1
	set v2, 16
	shl v1, v0, v2
	check_eq16 v1, 0, 6

	set v0, $8000
	set v2, 17
	shr v1, v0, v2
	check_eq16 v1, 0, 7

	set v1, data_area
	set v0, $005a
	strl v0, v1, 0
	set v0, $00a5
	strl v0, v1, 15

	set v2, 0
	ldrl v2, v1, 16
	check_eq16 v2, $005a, 8

	set v2, 0
	ldrl v2, v1, 15
	check_eq16 v2, $00a5, 9

	test_pass

fail:
	setl v3, TEST_STATUS
	seth v3, /TEST_STATUS
	strl v4, v3, 0
	b *

data_area:
	ds 16

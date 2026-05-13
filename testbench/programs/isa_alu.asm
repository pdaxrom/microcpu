include ../../asm/include/pseudo.inc
include ../include/test.inc

org $0000

	set v0, $00f0
	set v1, $000f
	add v2, v0, v1
	check_eq16 v2, $00ff, 1

	add v2, v0, 1
	check_eq16 v2, $00f1, 2

	set v0, 0
	sub v2, v0, 1
	check_eq16 v2, $ffff, 3

	set v0, $0001
	shl v2, v0, 4
	check_eq16 v2, $0010, 4

	set v0, $8000
	shr v2, v0, 15
	check_eq16 v2, $0001, 5

	set v0, $00f0
	set v1, $0f0f
	and v2, v0, v1
	check_eq16 v2, $0000, 6

	or v2, v0, v1
	check_eq16 v2, $0fff, 7

	xor v2, v0, v1
	check_eq16 v2, $0fff, 8

	set v0, $00ff
	inv v2, v0
	check_eq16 v2, $ff00, 9

	set v0, $0080
	sxt v2, v0
	check_eq16 v2, $ff80, 10

	set v0, $007f
	sxt v2, v0
	check_eq16 v2, $007f, 11

	set v0, $ffff
	add v2, v0, 1
	check_eq16 v2, $0000, 12

	test_pass

fail:
	setl v3, TEST_STATUS
	seth v3, /TEST_STATUS
	strl v4, v3, 0
	b *

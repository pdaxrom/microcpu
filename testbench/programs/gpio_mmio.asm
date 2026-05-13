include ../../asm/include/pseudo.inc
include ../../asm/include/devmap.inc
include ../include/test.inc

org $0000

	set v1, GPIO_ADDR

	set v0, $00ff
	strl v0, v1, 3
	set v0, $007f
	strl v0, v1, 2

	set v0, $00a5
	strl v0, v1, 1
	set v0, $002a
	strl v0, v1, 0

	set v0, 0
	ldrl v0, v1, 1
	check_eq16 v0, $00a5, 1

	set v0, 0
	ldrl v0, v1, 0
	check_eq16 v0, $00aa, 2

	set v0, 0
	ldrl v0, v1, 3
	check_eq16 v0, $00ff, 3

	set v0, 0
	ldrl v0, v1, 2
	check_eq16 v0, $00ff, 4

	test_pass

fail:
	setl v3, TEST_STATUS
	seth v3, /TEST_STATUS
	strl v4, v3, 0
	b *

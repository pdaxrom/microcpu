include ../../asm/include/pseudo.inc
include ../../asm/include/devmap.inc
include ../include/test.inc

org $0000

	set v1, UART_ADDR

	set v0, 0
	ldrl v0, v1, 0
	check_eq16 v0, 1, 1

	set v0, 0
	ldrl v0, v1, 1
	check_eq16 v0, 'R', 2

	set v0, 0
	ldrl v0, v1, 0
	check_eq16 v0, 0, 3

	set v2, TEST_UART_EXPECT
	setl v0, 'O'
	strl v0, v2, 0
	strl v0, v1, 1

	setl v0, 'K'
	strl v0, v2, 0
	strl v0, v1, 1

	test_pass

fail:
	setl v3, TEST_STATUS
	seth v3, /TEST_STATUS
	strl v4, v3, 0
	b *

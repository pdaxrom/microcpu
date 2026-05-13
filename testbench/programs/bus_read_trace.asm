include ../../asm/include/pseudo.inc
include ../include/test.inc

org $0000

	set v1, trace_data
	expect_read trace_data, $34
	expect_read trace_data + 1, $12
	ldr v0, v1, 0
	check_eq16 v0, $1234, 1

	set v0, 0
	expect_read trace_data + 2, $5a
	ldrl v0, v1, 2
	check_eq16 v0, $005a, 2

	set lr, 3
	set v0, 0
	expect_read trace_data + 3, $a5
	ldrl v0, v1, lr
	check_eq16 v0, $00a5, 3

	test_pass

fail:
	setl v3, TEST_STATUS
	seth v3, /TEST_STATUS
	strl v4, v3, 0
	b *

trace_data:
	db $34, $12, $5a, $a5

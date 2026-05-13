include ../../asm/include/pseudo.inc
include ../include/test.inc

org $0000

	set v1, trace_area
	set v0, $1234
	expect_write trace_area, $34
	expect_write trace_area + 1, $12
	str v0, v1, 0

	set v0, $00ab
	expect_write trace_area + 3, $ab
	strl v0, v1, 3

	set lr, 5
	set v0, $00cd
	expect_write trace_area + 5, $cd
	strl v0, v1, lr

	test_pass

fail:
	setl v3, TEST_STATUS
	seth v3, /TEST_STATUS
	strl v4, v3, 0
	b *

trace_area:
	ds 8

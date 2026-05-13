include ../../asm/include/pseudo.inc
include ../include/test.inc

org $0000

	test_pass

fail:
	setl v3, TEST_STATUS
	seth v3, /TEST_STATUS
	strl v4, v3, 0
	b *

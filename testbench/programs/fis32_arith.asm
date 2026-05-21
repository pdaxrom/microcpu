include ../../asm/include/pseudo.inc
include ../include/test.inc

org $0000

	set sp, stack_top

	; 1.0 + 2.0 = 3.0
	set v0, $0000
	set v1, $4080
	set v2, $0000
	set v3, $4100
	bsr f32add
	check_eq16 v0, $0000, 1
	check_eq16 v1, $4140, 2

	; 1.0 + -1.0 = 0.0
	set v0, $0000
	set v1, $4080
	set v2, $0000
	set v3, $c080
	bsr f32add
	check_eq16 v0, 0, 3
	check_eq16 v1, 0, 4

	; 5.0 - 2.0 = 3.0
	set v0, $0000
	set v1, $41a0
	set v2, $0000
	set v3, $4100
	bsr f32sub
	check_eq16 v0, $0000, 5
	check_eq16 v1, $4140, 6

	; 1.5 * 2.0 = 3.0
	set v0, $0000
	set v1, $40c0
	set v2, $0000
	set v3, $4100
	bsr f32mul
	check_eq16 v0, $0000, 7
	check_eq16 v1, $4140, 8

	; 1.0 / 1.5 = 0.666...
	set v0, $0000
	set v1, $4080
	set v2, $0000
	set v3, $40c0
	bsr f32div
	check_eq16 v0, $aaab, 9
	check_eq16 v1, $402a, 10

	; Division by zero saturates to max finite value.
	set v0, $0000
	set v1, $4080
	set v2, 0
	set v3, 0
	bsr f32div
	check_eq16 v0, $ffff, 11
	check_eq16 v1, $7fff, 12

	test_pass

fail:
	setl v3, TEST_STATUS
	seth v3, /TEST_STATUS
	strl v4, v3, 0
	b *

include ../../asm/include/fis32.inc

ds 256
stack_top:

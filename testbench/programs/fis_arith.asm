include ../../asm/include/pseudo.inc
include ../include/test.inc

org $0000

	set sp, stack_top

	; 1.0 + 2.0 = 3.0
	set v0, $8000
	set v1, $0080
	set v2, $8000
	set v3, $0081
	bsr fadd
	check_eq16 v0, $c000, 1
	check_eq16 v1, $0081, 2

	; 1.0 + 0.5 = 1.5
	set v0, $8000
	set v1, $0080
	set v2, $8000
	set v3, $007f
	bsr fadd
	check_eq16 v0, $c000, 3
	check_eq16 v1, $0080, 4

	; 1.0 + -1.0 = 0.0
	set v0, $8000
	set v1, $0080
	set v2, $8000
	set v3, $8080
	bsr fadd
	check_eq16 v0, 0, 5
	check_eq16 v1, 0, 6

	; 5.0 - 2.0 = 3.0
	set v0, $a000
	set v1, $0082
	set v2, $8000
	set v3, $0081
	bsr fsub
	check_eq16 v0, $c000, 7
	check_eq16 v1, $0081, 8

	; 1.5 * 2.0 = 3.0
	set v0, $c000
	set v1, $0080
	set v2, $8000
	set v3, $0081
	bsr fmul
	check_eq16 v0, $c000, 9
	check_eq16 v1, $0081, 10

	; -1.5 * 2.0 = -3.0
	set v0, $c000
	set v1, $8080
	set v2, $8000
	set v3, $0081
	bsr fmul
	check_eq16 v0, $c000, 11
	check_eq16 v1, $8081, 12

	; 1.0 / 1.5 = 0.666..., normalized after division.
	set v0, $8000
	set v1, $0080
	set v2, $c000
	set v3, $0080
	bsr fdiv
	check_eq16 v0, $aaaa, 13
	check_eq16 v1, $007f, 14

	; -6.0 / 2.0 = -3.0
	set v0, $c000
	set v1, $8082
	set v2, $8000
	set v3, $0081
	bsr fdiv
	check_eq16 v0, $c000, 15
	check_eq16 v1, $8081, 16

	; 2.0 - 5.0 = -3.0
	set v0, $8000
	set v1, $0081
	set v2, $a000
	set v3, $0082
	bsr fsub
	check_eq16 v0, $c000, 17
	check_eq16 v1, $8081, 18

	; 1.0 * 0.0 = 0.0
	set v0, $8000
	set v1, $0080
	set v2, 0
	set v3, 0
	bsr fmul
	check_eq16 v0, 0, 19
	check_eq16 v1, 0, 20

	; Smallest normalized values underflow to zero on multiply.
	set v0, $8000
	set v1, $0001
	set v2, $8000
	set v3, $0001
	bsr fmul
	check_eq16 v0, 0, 21
	check_eq16 v1, 0, 22

	; Overflow saturates to max finite value with sign.
	set v0, $ffff
	set v1, $80ff
	set v2, $8000
	set v3, $0081
	bsr fmul
	check_eq16 v0, $ffff, 23
	check_eq16 v1, $80ff, 24

	; Division by zero saturates to max finite value with quotient sign.
	set v0, $8000
	set v1, $0080
	set v2, 0
	set v3, 0
	bsr fdiv
	check_eq16 v0, $ffff, 25
	check_eq16 v1, $00ff, 26

	set v0, $8000
	set v1, $8080
	set v2, 0
	set v3, 0
	bsr fdiv
	check_eq16 v0, $ffff, 27
	check_eq16 v1, $80ff, 28

	test_pass

fail:
	setl v3, TEST_STATUS
	seth v3, /TEST_STATUS
	strl v4, v3, 0
	b *

include ../../asm/include/fis.inc

ds 128
stack_top:

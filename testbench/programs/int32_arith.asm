include ../../asm/include/pseudo.inc
include ../include/test.inc

org $0000

	set sp, stack_top

	set v0, $ffff
	set v1, 0
	set v2, 1
	set v3, 0
	bsr u32_add
	check_eq16 v0, $0000, 1
	check_eq16 v1, $0001, 2

	set v0, 0
	set v1, 1
	set v2, 1
	set v3, 0
	bsr u32_sub
	check_eq16 v0, $ffff, 3
	check_eq16 v1, $0000, 4

	set v0, 2
	set v1, 1
	set v2, 3
	set v3, 0
	bsr u32_mul
	check_eq16 v0, 6, 5
	check_eq16 v1, 3, 6

	set v0, $ffff
	set v1, $ffff
	set v2, 2
	set v3, 0
	bsr u32_mul
	check_eq16 v0, $fffe, 7
	check_eq16 v1, $ffff, 8

	set v0, $0000
	set v1, $0001
	set v2, 2
	set v3, 0
	bsr u32_div
	check_eq16 v0, $8000, 9
	check_eq16 v1, $0000, 10
	check_eq16 v2, $0000, 11
	check_eq16 v3, $0000, 12

	set v0, 7
	set v1, 0
	set v2, 3
	set v3, 0
	bsr u32_div
	check_eq16 v0, 2, 13
	check_eq16 v1, 0, 14
	check_eq16 v2, 1, 15
	check_eq16 v3, 0, 16

	set v0, $fff9
	set v1, $ffff
	set v2, 3
	set v3, 0
	bsr i32_div
	check_eq16 v0, $fffe, 17
	check_eq16 v1, $ffff, 18
	check_eq16 v2, $ffff, 19
	check_eq16 v3, $ffff, 20

	set v0, 7
	set v1, 0
	set v2, $fffd
	set v3, $ffff
	bsr i32_div
	check_eq16 v0, $fffe, 21
	check_eq16 v1, $ffff, 22
	check_eq16 v2, 1, 23
	check_eq16 v3, 0, 24

	set v0, $ffff
	set v1, 0
	bsr u32_shl1
	check_eq16 v0, $fffe, 25
	check_eq16 v1, 1, 26

	set v0, 0
	set v1, 1
	bsr u32_shr1
	check_eq16 v0, $8000, 27
	check_eq16 v1, 0, 28

	set v0, 0
	set v1, $8001
	bsr i32_sar1
	check_eq16 v0, $8000, 29
	check_eq16 v1, $c000, 30

	set v0, 1
	set v1, 0
	set v2, 4
	bsr u32_shl
	check_eq16 v0, $0010, 31
	check_eq16 v1, $0000, 32

	set v0, 0
	set v1, 1
	set v2, 4
	bsr u32_shr
	check_eq16 v0, $1000, 33
	check_eq16 v1, $0000, 34

	set v0, 0
	set v1, $8000
	set v2, 4
	bsr i32_sar
	check_eq16 v0, $0000, 35
	check_eq16 v1, $f800, 36

	set v0, $8000
	set v1, $8000
	set v4, 1
	bsr u32_shl1c
	mov v2, v4
	check_eq16 v0, $0001, 37
	check_eq16 v1, $0001, 38
	check_eq16 v2, 1, 39

	set v0, 1
	set v1, 0
	set v4, 1
	bsr u32_shr1c
	mov v2, v4
	check_eq16 v0, $0000, 40
	check_eq16 v1, $8000, 41
	check_eq16 v2, 1, 42

	test_pass

fail:
	setl v3, TEST_STATUS
	seth v3, /TEST_STATUS
	strl v4, v3, 0
	b *

include ../../asm/include/int32.inc

ds 96
stack_top:

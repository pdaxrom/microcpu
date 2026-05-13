include ../../asm/include/pseudo.inc
include ../include/test.inc

org $0000

	set v0, $1234
	check_eq16 v0, $1234, 1

	set v1, $00ab
	movl v0, v1
	check_eq16 v0, $12ab, 2

	movh v0, v1
	check_eq16 v0, $abab, 3

	mov v2, v0
	check_eq16 v2, $abab, 4

	set v1, data_area
	set v0, $1234
	str v0, v1, 0
	set v2, 0
	ldr v2, v1, 0
	check_eq16 v2, $1234, 5

	set v2, 0
	ldrl v2, v1, 0
	check_eq16 v2, $0034, 6

	set v2, 0
	ldrl v2, v1, 1
	check_eq16 v2, $0012, 7

	set v0, $00cd
	strl v0, v1, 2
	set v2, 0
	ldrl v2, v1, 2
	check_eq16 v2, $00cd, 8

	set lr, 4
	set v0, $55aa
	str v0, v1, lr
	set v2, 0
	ldr v2, v1, lr
	check_eq16 v2, $55aa, 9

	set lr, 6
	set v0, $00ee
	strl v0, v1, lr
	set v2, 0
	ldrl v2, v1, lr
	check_eq16 v2, $00ee, 10

	set v1, word_bytes
	set v2, 0
	ldr v2, v1, 0
	check_eq16 v2, $beef, 11

	test_pass

fail:
	setl v3, TEST_STATUS
	seth v3, /TEST_STATUS
	strl v4, v3, 0
	b *

data_area:
	ds 16

word_bytes:
	db $ef, $be

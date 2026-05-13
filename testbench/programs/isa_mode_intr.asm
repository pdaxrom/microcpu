include ../../asm/include/pseudo.inc
include ../include/test.inc

org $0000

	b start
	b isr

start:
	set sp, stack_top

	set v0, $3456
	setp v0
	getp v2
	check_eq16 v2, $3456, 1

	set v0, 0
	sws

	set v1, irq_count
	ldr v0, v1, 0
	check_eq16 v0, 1, 2

	set v1, TEST_INTR
	setl v0, 1
	strl v0, v1, 0
	nop
	nop
	nop
	nop

	set v1, irq_count
	ldr v0, v1, 0
	check_eq16 v0, 2, 3

	test_pass

isr:
	set v1, irq_count
	ldr v0, v1, 0
	add v0, v0, 1
	str v0, v1, 0
	swu

fail:
	setl v3, TEST_STATUS
	seth v3, /TEST_STATUS
	strl v4, v3, 0
	b *

irq_count:
	dw 0

	ds 32
stack_top:

include ../../asm/include/pseudo.inc
include ../include/test.inc

org $0000

	b start
	b isr

start:
	set sp, stack_top
	set v1, irq_count
	set v0, 0
	str v0, v1, 0
	set v1, nested_phase
	str v0, v1, 0

	set v1, TEST_INTR
	setl v0, 4
	strl v0, v1, 0
	set v0, $1000
	set v1, $0001
	add v2, v0, v1
	check_eq16 v2, $1001, 1
	set v1, irq_count
	ldr v0, v1, 0
	check_eq16 v0, 1, 2

	set v1, TEST_INTR
	setl v0, 5
	strl v0, v1, 0
	set v1, data_area
	ldr v2, v1, 0
	check_eq16 v2, $55aa, 3
	set v1, irq_count
	ldr v0, v1, 0
	check_eq16 v0, 2, 4

	set v1, nested_phase
	set v0, 1
	str v0, v1, 0

	set v1, irq_count
	sws
	set v1, irq_count
	ldr v0, v1, 0
	check_eq16 v0, 4, 5

	test_pass

isr:
	set v4, isr_save
	str v0, v4, 0
	str v1, v4, 2
	str v2, v4, 4

	set v1, irq_count
	ldr v0, v1, 0
	add v0, v0, 1
	str v0, v1, 0

	set v1, nested_phase
	ldr v2, v1, 0
	eq v2, 1
	b isr_restore

	set v1, TEST_INTR
	setl v2, 1
	strl v2, v1, 0
	nop
	nop
	nop

	set v1, nested_phase
	set v2, 0
	str v2, v1, 0

	set v1, irq_count
	ldr v2, v1, 0
	setl v4, 6
	eq v2, 3
	b fail

isr_restore:
	set v4, isr_save
	ldr v2, v4, 4
	ldr v1, v4, 2
	ldr v0, v4, 0
	swu

fail:
	setl v3, TEST_STATUS
	seth v3, /TEST_STATUS
	strl v4, v3, 0
	b *

irq_count:
	dw 0
nested_phase:
	dw 0
data_area:
	dw $55aa
isr_save:
	dw 0, 0, 0

	ds 32
stack_top:

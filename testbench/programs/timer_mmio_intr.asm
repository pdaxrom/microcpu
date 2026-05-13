include ../../asm/include/pseudo.inc
include ../../asm/include/devmap.inc
include ../include/test.inc

org $0000

	b start
	b isr

start:
	set sp, stack_top
	set v1, irq_count
	set v0, 0
	str v0, v1, 0

	set v1, TIMER_ADDR
	set v0, 8
	str v0, v1, 0

	set v1, irq_count
wait_irq:
	ldr v0, v1, 0
	eq v0, 1
	b wait_irq

got_irq:
	ldrl v0, v1, 0
	check_eq16 v0, 1, 1
	test_pass

isr:
	set v4, isr_save
	str v0, v4, 0
	str v1, v4, 2

	set v1, irq_count
	ldr v0, v1, 0
	add v0, v0, 1
	str v0, v1, 0
	set v1, TIMER_ADDR
	ldrl v0, v1, 2

	set v4, isr_save
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
isr_save:
	dw 0, 0

	ds 32
stack_top:

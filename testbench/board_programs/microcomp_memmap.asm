include ../../asm/include/pseudo.inc
include ../../asm/include/devmap.inc

org $0000

	b start
	b isr

start:
	set v1, irq_count
	set v0, 0
	str v0, v1, 0

	set v1, $6000
	ldrl v0, v1, 0

wait_irq:
	set v1, irq_count
	ldr v0, v1, 0
	eq v0, 1
	b wait_irq

	set v1, $6000
	setl v0, $5a
	strl v0, v1, 0

	set v1, MMAP_ADDR
	set v0, 0
	ldrl v0, v1, 0
	set v2, $61
	eq v0, v2
	b fail

pass:
	set v1, UART_ADDR
	setl v0, 'P'
	strl v0, v1, 1
	b *

isr:
	set v1, MMAP_ADDR
	set v0, 0
	ldrl v0, v1, 2
	set v2, $60
	eq v0, v2
	b fail
	strl v0, v1, 0

	set v1, irq_count
	ldr v0, v1, 0
	add v0, v0, 1
	str v0, v1, 0
	swu

fail:
	set v1, UART_ADDR
	setl v0, 'F'
	strl v0, v1, 1
	b *

irq_count:
	dw 0

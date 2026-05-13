include ../../asm/include/pseudo.inc
include ../../asm/include/devmap.inc

org $0000

	b start
	b isr

start:
	set v1, irq_count
	set v0, 0
	str v0, v1, 0

	set v1, $07ff
	setl v0, $11
	strl v0, v1, 0
	ldrl v2, v1, 0
	setl v4, 1
	eq v2, v0
	b fail

	set v1, $0800
	setl v0, $22
	strl v0, v1, 0
	ldrl v2, v1, 0
	setl v4, 2
	eq v2, v0
	b fail

	set v1, $0fff
	setl v0, $33
	strl v0, v1, 0
	ldrl v2, v1, 0
	setl v4, 3
	eq v2, v0
	b fail

	set v1, MMAP_ADDR
	set v0, 0
	ldrl v0, v1, 0
	set v2, $09
	setl v4, 4
	eq v0, v2
	b fail
	set v0, $08
	strl v0, v1, 0

	set v1, $1000
	setl v0, $44
	strl v0, v1, 0
	ldrl v2, v1, 0
	setl v4, 5
	eq v2, v0
	b fail

	set v1, $17ff
	setl v0, $55
	strl v0, v1, 0
	ldrl v2, v1, 0
	setl v4, 6
	eq v2, v0
	b fail

	set v1, MMAP_ADDR
	set v0, 0
	ldrl v0, v1, 1
	set v2, $11
	setl v4, 7
	eq v0, v2
	b fail
	set v0, $10
	strl v0, v1, 1

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
	setl v4, 8
	eq v0, v2
	b fail

	set v1, $6800
	ldrl v0, v1, 0

wait_irq2:
	set v1, irq_count
	ldr v0, v1, 0
	eq v0, 2
	b wait_irq2

	set v1, $6800
	setl v0, $a5
	strl v0, v1, 0

	set v1, MMAP_ADDR
	set v0, 0
	ldrl v0, v1, 1
	set v2, $69
	setl v4, 9
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
	setl v4, 10
	eq v0, v2
	b isr_check_page2
	strl v0, v1, 0
	b isr_count

isr_check_page2:
	set v2, $68
	setl v4, 11
	eq v0, v2
	b fail
	strl v0, v1, 1

isr_count:
	set v1, irq_count
	ldr v0, v1, 0
	add v0, v0, 1
	str v0, v1, 0
	swu

fail:
	set v1, UART_ADDR
	setl v0, '0'
	add v0, v0, v4
	strl v0, v1, 1
	b *

irq_count:
	dw 0

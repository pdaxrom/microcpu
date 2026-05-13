include ../../asm/include/pseudo.inc
include ../../asm/include/devmap.inc

org $0000

	set v1, UART_ADDR
	setl v0, 'M'
	strl v0, v1, 1
	b *

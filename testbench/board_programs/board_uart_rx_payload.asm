include ../../asm/include/pseudo.inc
include ../../asm/include/devmap.inc

org $0800

	set v1, UART_ADDR
	setl v0, 'R'
	strl v0, v1, 1
	b *
	db $7e, 0, 0, $7e

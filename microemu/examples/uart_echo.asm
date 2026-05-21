;
; Read one byte from the emulated UART RX queue and echo it to UART TX.
; Build: make -C microemu build/examples/uart_echo.bin
; Run:   make -C microemu run-echo
;

include ../../asm/include/pseudo.inc
include ../../asm/include/devmap.inc

org $0000

	set	v1, UART_ADDR

wait_rx:
	ldrl	v0, v1, 0
	bitne	wait_rx, v0, 1

	ldrl	v0, v1, 1

wait_tx:
	ldrl	v2, v1, 0
	biteq	wait_tx, v2, 2

	strl	v0, v1, 1
	b	*

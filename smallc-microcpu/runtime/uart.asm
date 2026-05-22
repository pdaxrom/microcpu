;
; Minimal UART stdio helpers for the Small-C microcpu backend.
;

__cc_uart_addr	equ	$ffe0

_putchar:
	ldr	v0, sp, 2
	seth	v0, 0
	set	v1, __cc_uart_addr
__putchar_wait_tx:
	ldrl	v2, v1, 0
	biteq	__putchar_wait_tx, v2, 2
	strl	v0, v1, 1
	rts

_puts:
	ldr	v1, sp, 2
	set	v2, __cc_uart_addr
__puts_loop:
	ldrl	v0, v1, 0
	seth	v0, 0
	eq	v0, 0
	b	__puts_write_char
	set	v0, 10
__puts_wait_newline:
	ldrl	v3, v2, 0
	biteq	__puts_wait_newline, v3, 2
	strl	v0, v2, 1
	clr	v0
	rts
__puts_write_char:
	ldrl	v3, v2, 0
	biteq	__puts_write_char, v3, 2
	strl	v0, v2, 1
	add	v1, v1, 1
	b	__puts_loop

_getchar:
	set	v1, __cc_uart_addr
__getchar_wait_rx:
	ldrl	v2, v1, 0
	bitne	__getchar_wait_rx, v2, 1
	ldrl	v0, v1, 1
	seth	v0, 0
	rts

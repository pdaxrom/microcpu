;
; Minimal hc1200-mcu UART example for microemu.
; Build: make -C microemu build/examples/hello_world.bin
; Run:   make -C microemu run-hello
;

include ../../asm/include/pseudo.inc
include ../../asm/include/devmap.inc

org $0000

	set	v1, UART_ADDR
	set	v2, message
	seth	v0, 0

next_char:
	ldrl	v0, v2, 0
	beq	done, v0, 0

wait_tx:
	ldrl	v3, v1, 0
	biteq	wait_tx, v3, 2

	strl	v0, v1, 1
	add	v2, v2, 1
	b	next_char

done:
	b	*

message:
	db	"Hello, World!", 10, 13, 0

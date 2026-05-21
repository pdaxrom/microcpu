;
; Synthetic hc1200-cpu smoke test: high RAM with hc1200 peripherals.
; Build: make -C microemu build/examples/ram64.bin
; Run:   make -C microemu run-ram64
;

include ../../asm/include/pseudo.inc
include ../../asm/include/devmap.inc

org $0000

	set	v0, $1234
	set	v1, $8000
	str	v0, v1, 0
	ldr	v2, v1, 0
	eq	v2, v0
	b	fail

	set	v0, $5aa5
	set	v1, $ffdc
	str	v0, v1, 0
	ldr	v2, v1, 0
	eq	v2, v0
	b	fail

	setl	v4, 0
	seth	v4, 0
	set	v2, ok_message
	b	print_loop

fail:
	setl	v4, 1
	seth	v4, 0
	set	v2, err_message

print_loop:
	set	v1, UART_ADDR
	seth	v0, 0

print_next:
	ldrl	v0, v2, 0
	beq	done, v0, 0

wait_tx:
	ldrl	v3, v1, 0
	biteq	wait_tx, v3, 2

	strl	v0, v1, 1
	add	v2, v2, 1
	b	print_next

done:
	eq	v4, 0
	b	bad_exit
	b	*

bad_exit:
	setl	v0, 1
	seth	v0, 0
	mov	pc, v0

ok_message:
	db	"RAM64 OK", 10, 13, 0

err_message:
	db	"RAM64 ERR", 10, 13, 0

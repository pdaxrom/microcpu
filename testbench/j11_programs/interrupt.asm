	cpu dcj-11
	org 0

	mov #02000, sp
wait_for_interrupt
	br wait_for_interrupt

code_end
	ds 060-code_end
	dw interrupt_handler
	dw 0

interrupt_handler
	mov #012345, r0
	rti

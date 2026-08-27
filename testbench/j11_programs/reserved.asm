	cpu dcj-11
	org 0

	mov #02000, sp
	dw 0xffff
	halt
	dw reserved_handler
	dw 0

reserved_handler
	mov #012345, r0
	rti

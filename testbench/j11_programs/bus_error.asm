	cpu dcj-11
	org 0

	br start
	dw 0
	dw bus_error_handler
	dw 0

start
	mov #02000, sp
	mov @#01001, r0	; odd word access must enter vector 004
	halt

bus_error_handler
	mov #065432, r0
	rti

	cpu dcj-11
	org 0

	br start

	org 014
	dw priority_handler
	dw 000200		; run BPT handler at priority 4

	org 060
	dw interrupt_handler
	dw 000200

	org 0100
start
	mov #02000, sp
	clr r0
	bpt
after_bpt
	mov #3, r1
	halt

priority_handler
	mov #1, r1		; testbench injects BR4 after seeing this marker
	mov #040, r2
priority_delay
	sob r2, priority_delay
	mov #2, r1
	rti

interrupt_handler
	mov #012345, r0
	rti

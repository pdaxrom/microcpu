	cpu dcj-11
	org 0

start
	nop
	br halt_here
	dw 0xffff		; BR must skip this reserved instruction

halt_here
	halt

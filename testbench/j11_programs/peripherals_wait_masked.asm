	cpu dcj-11
	org 0
	mov #010000, sp
	spl 6
	clr @#0177546
	mov #0100, @#0177546
	mov #1, r0
	wait
	clr r0 ; a masked clock must never reach this instruction
	halt

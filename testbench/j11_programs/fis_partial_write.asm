; A fault on the low result word (06006) must not consume the FIS stack or
; commit condition codes. The preceding successful high-word write remains.
	cpu dcj-11
	macro check
	cmp #1, #2
	beq *+6
	jmp @#failed
	endm
	org 0
	jmp @#start
	org 4
	dw bus_error
	dw 0340
	org 010
	dw failed
	dw 0340
	org 01000
start
	mov #010000, sp
	mov #1, r5
	mov #operands, r0
	clr r3
	mov #3, @#0177776
	fadd r0
after_add
	check #1, r3
	check #operands, r0
	check #040400, @#operands+4
	check #0, @#operands+6
	check #010000, sp
	mov #012345, r0
	halt
bus_error
	check #after_add, (sp)
	check #3, 2(sp)
	check #040, @#0177766
	inc r3
	rti
failed
	halt
	org 06000
operands
	dw 040200, 0, 040200, 0

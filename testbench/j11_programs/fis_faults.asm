; Run with read fault 06006, or write fault 06004. Each operation must abort
; through vector 004 without committing Rn/NZVC or changing the destination.
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
	org 0244
	dw failed
	dw 0340
	org 01000
start
	mov #010000, sp
	mov #operands, r0
	clr r3
	mov #1, r5
	mov #after_add, r4
	mov #3, @#0177776
	fadd r0
after_add
	mov #2, r5
	mov #after_sub, r4
	mov #3, @#0177776
	fsub r0
after_sub
	mov #3, r5
	mov #after_mul, r4
	mov #3, @#0177776
	fmul r0
after_mul
	mov #4, r5
	mov #after_div, r4
	mov #3, @#0177776
	fdiv r0
after_div
	check #4, r3
	check #operands, r0
	check #010000, sp
	check #040200, @#operands+4
	mov #012345, r0
	halt
bus_error
	check r4, (sp)
	check #3, 2(sp)
	check #040, @#0177766
	check #operands, r0
	check #040200, @#operands
	check #040200, @#operands+4
	clr @#0177766
	inc r3
	rti
failed
	halt
	org 06000
operands
	dw 040200, 0, 040200, 0

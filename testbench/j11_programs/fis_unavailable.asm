	; FIS is deferred for lack of uROM, not silently mapped to FP11 or NOP.
	cpu dcj-11
	macro check
	cmp #1, #2
	beq *+6
	jmp @#failed
	endm
	org 0
	jmp @#start
	org 4
	dw failed
	dw 0340
	org 010
	dw reserved
	dw 0340
	org 01000
start
	mov #010000, sp
	mov #0177774, r0 ; an operand read would itself bus-fault
	clr r4
	mov #1, r5
	mov #after_add, r3
	mov #3, @#0177776
	fadd r0
after_add
	mov #2, r5
	mov #after_sub, r3
	mov #3, @#0177776
	fsub r0
after_sub
	mov #3, r5
	mov #after_mul, r3
	mov #3, @#0177776
	fmul r0
after_mul
	mov #4, r5
	mov #after_div, r3
	mov #3, @#0177776
	fdiv r0
after_div
	check #4, r4
	check #0177774, r0
	check #010000, sp
	check #0, @#0177766
	mov #012345, r0
	halt
reserved
	check r3, (sp)
	check #3, 2(sp)
	inc r4
	rti
failed
	mov r5, r0
	halt

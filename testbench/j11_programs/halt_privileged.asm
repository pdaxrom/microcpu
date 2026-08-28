	cpu dcj-11
	macro check
	cmp #1, #2
	beq *+6
	jmp @#failed
	endm
	org 0
	jmp @#start
	org 4
	dw illegal_halt
	dw 0340
	org 01000
start
	mov #010000, sp
	mov #0100, r0
	mov #04000, @#0177776
	mov #0200, r0
	clr @#0177776
	mov #040000, @#expected_psw
	mov #after_s0, @#expected_pc
	mov #040000, @#0177776
	mov #012000, sp
	mov #040000, @#0177776
	halt
after_s0
	check #0100, r0
	check #012000, sp
	mov #044000, @#expected_psw
	mov #after_s1, @#expected_pc
	mov #044000, @#0177776
	halt
after_s1
	check #0200, r0
	check #012000, sp
	mov #0140000, @#expected_psw
	mov #after_u0, @#expected_pc
	mov #0140000, @#0177776
	mov #014000, sp
	mov #0140000, @#0177776
	halt
after_u0
	check #0100, r0
	check #014000, sp
	mov #0144000, @#expected_psw
	mov #after_u1, @#expected_pc
	mov #0144000, @#0177776
	halt
after_u1
	check #0200, r0
	check #014000, sp
	clr @#0177776
	check #010000, sp
	check #4, @#count
	check #0, @#0177766
	mov #012345, r0
	halt
illegal_halt
	check #0100, r0
	check #07774, sp
	check @#expected_pc, (sp)
	check @#expected_psw, 2(sp)
	check #0200, @#0177766
	clr @#0177766
	inc @#count
	rti
failed
	clr @#0177776
	mov #0177777, r0
	halt
expected_pc
	dw 0
expected_psw
	dw 0
count
	dw 0

	cpu dcj-11
	macro check
	cmp #1, #2
	beq *+6
	jmp @#failed
	endm
	macro init_args
	mov #(040200), @#operands
	clr @#operands+2
	mov #(040200), @#operands+4
	clr @#operands+6
	endm
	macro test_register reg
	init_args
	mov #operands, reg
	fadd reg
	check #operands+4, reg
	check #(040400), @#operands+4
	check #(0), @#operands+6
	endm
	org 0
	jmp @#start
	org 4
	dw address_error
	dw 0340
	org 010
	dw illegal
	dw 0340
	org 014
	dw trace_handler
	dw 0340
	org 030
	dw user_finished
	dw 0340
	org 0244
	dw user_error
	dw 0340
	org 01000
start
	mov #010000, sp
	test_register r0
	test_register r1
	test_register r2
	test_register r3
	test_register r4
	test_register r5
	test_register sp
	mov #010000, sp
	mov #010, r5

	; R7 points at the inline B. On success it advances to the high answer,
	; which is itself a branch instruction (A + dirty zero = A unchanged).
pc_operation
	fadd pc
	dw 0100001, 0777
pc_answer
	br pc_done
	dw 01234
	dw 0, 0
pc_done
	check #01234, @#pc_answer+2

	; Every FIS rejects an odd operand pointer through vector 004.
	mov #011, r5
	clr r3
	mov #operands+1, r0
	mov #after_add, r4
	mov #3, @#0177776
	fadd r0
after_add
	mov #after_sub, r4
	mov #3, @#0177776
	fsub r0
after_sub
	mov #after_mul, r4
	mov #3, @#0177776
	fmul r0
after_mul
	mov #after_div, r4
	mov #3, @#0177776
	fdiv r0
after_div
	check #4, r3
	check #operands+1, r0
	check #010000, sp

	; Adjacent reserved encodings must NOT enter FIS or read odd R0.
	mov #012, r5
	clr r3
	dw 075040, 075077, 075100, 075777 ; deliberately invalid instructions
	check #4, r3
	check #0, @#0177766

	; Normal FIS commits its result before the ordinary TRACE boundary.
	mov #013, r5
	init_args
	mov #operands, r1
	clr r3
	mov #0360, -(sp)
	mov #traced_fis, -(sp)
	rtt
traced_fis
	fadd r1
after_trace
	check #1, r3
	check #operands+4, r1
	check #040400, @#operands+4

	; FIS using user SP: ordinary success then divide-by-zero switches to
	; KSP for its frame without consuming the user floating-point stack.
	mov #014, r5
	init_args
	mov #0140340, -(sp)
	mov #user_start, -(sp)
	rti
user_start
	mov #operands, sp
	fadd sp
	check #operands+4, sp
	check #040400, @#operands+4
	clr @#operands
	mov #operands, sp
	mov #user_after_error, r4
	fdiv sp
user_after_error
	check #operands, sp
	emt 0
	jmp @#failed
user_error
	check r4, (sp)
	check #0140353, 2(sp)
	check #07774, sp
	mfpi sp
	mov (sp)+, r2
	check #operands, r2
	check #0, @#operands
	check #040400, @#operands+4
	rti
user_finished
	check #07774, sp
	mfpi sp
	mov (sp)+, r2
	check #operands, r2
	mov #012345, r0
	halt
trace_handler
	check #after_trace, (sp)
	check #0360, 2(sp)
	bic #020, 2(sp)
	inc r3
	rti
address_error
	check #011, r5
	check r4, (sp)
	check #3, 2(sp)
	check #0100, @#0177766
	clr @#0177766
	inc r3
	rti
illegal
	check #012, r5
	inc r3
	rti
failed
	halt
	org 06000
operands
	dw 0, 0, 0, 0

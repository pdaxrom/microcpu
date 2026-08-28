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
	org 014
	dw traced
	dw 04340
	org 060
	dw interrupted
	dw 04340
	; Assembled label metadata, used only for testbench stop-point assertions.
	org 0100
	dw first_proceed
	dw step_instruction
	dw after_step
	dw after_wait
	dw traced_proceed
	dw after_vector_halt
	org 01000
start
	mov #010000, sp
	mov #0100, r0
	mov #0101, r1
	mov #0102, r2
	mov #0103, r3
	mov #0104, r4
	mov #0105, r5
	mov #04000, @#0177776
	mov #0200, r0
	mov #0201, r1
	mov #0202, r2
	mov #0203, r3
	mov #0204, r4
	mov #0205, r5
	mov #1, @#stage
	mov #04013, @#0177776
	halt
first_proceed
	inc @#steps
after_first_step
	check #1, @#interrupts
	check #1, @#steps
	check #0200, r0
	check #0205, r5
	check #010000, sp
	mov #2, @#stage
	mov #04003, @#0177776
	halt
step_instruction
	inc @#steps
after_step
	; Held HALT + Proceed must stop before this instruction.
	bpt
after_vector_halt
	; Held HALT takes precedence at vector entry, without building a frame.
	check #2, @#steps
	mov #3, @#stage
	mov #0144000, @#0177776
	mov #014000, sp
	wait
after_wait
	; The firmware HALT request can stop WAIT in user mode without trap 004.
	inc @#steps
	check #3, @#steps
	check #014000, sp
	check #0200, r0
	check #0, @#0177766
	mov #04000, @#0177776
	check #010000, sp
	mov #4, @#stage
	mov #04020, -(sp)
	mov #traced_halt, -(sp)
	rtt
traced_halt
	halt
traced_proceed
	inc @#steps
after_trace_step
	check #1, @#traces
	check #4, @#steps
	clr @#0177776
	check #0100, r0
	check #0101, r1
	check #0102, r2
	check #0103, r3
	check #0104, r4
	check #0105, r5
	check #010000, sp
	mov #5, @#stage
	mov #012345, r0
	halt
interrupted
	check #1, @#steps
	check #after_first_step, (sp)
	check #04001, 2(sp)
	inc @#interrupts
	rti
traced
	check #after_trace_step, (sp)
	check #4, @#steps
	inc @#traces
	bic #020, 2(sp)
	rtt
failed
	clr @#0177776
	mov #0177777, r0
	halt
	org 06000
stage
	dw 0
steps
	dw 0
interrupts
	dw 0
traces
	dw 0

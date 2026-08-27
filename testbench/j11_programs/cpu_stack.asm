	cpu dcj-11
	macro check
	cmp #1, #2
	beq *+6
	jmp @#failed
	endm
	org 0
	jmp @#start
	org 4
	dw stack_fault
	dw 0340
	org 014
	dw bpt_target
	dw 0340
	org 01000
start
	mov #010000, sp
	clr r4
	mov #1, r5
	mov #0402, sp
	mov #0777, -(sp) ; address 0400 is allowed
	check #0400, sp
	check #0, @#0177766
	check #0777, (sp)
	mov #after_word, r3
	mov #3, @#0177776
	mov #01234, -(sp)
after_word
	check #0376, sp
	check #01234, (sp)
	check #1, r4
	clr @#0177766

	mov #2, r5
	mov #after_byte, r3
	mov #0400, sp
	movb #0200, -(sp) ; SP still decrements by TWO for byte operations
after_byte
	check #0376, sp
	movb (sp), r0
	check #0177600, r0
	clr @#0177766

	mov #3, r5
	mov #after_deferred, r3
	mov #06000, @#0376
	mov #0400, sp
	mov #0444, @-(sp) ; check the stack pointer, not the final EA
after_deferred
	check #0376, sp
	check #0444, @#06000
	clr @#0177766

	mov #4, r5
	mov #after_read, r3
	mov #0400, sp
	mov -(sp), r1 ; reads through autodecrement SP count too
after_read
	check #06000, r1
	clr @#0177766

	mov #5, r5
	mov #callee, r3
	mov #01234, r2
	mov #0400, sp
	jsr r2, @#callee
after_jsr
	check #01234, r2
	check #0400, sp
	clr @#0177766

	mov #6, r5
	mov #after_mfpi, r3
	mov #0456, r1
	mov #0400, sp
	mfpi r1
after_mfpi
	check #0376, sp
	check #0456, (sp)
	clr @#0177766

	mov #7, r5
	mov #bpt_target, r3
	mov #0400, sp
	bpt ; yellow follows the BPT frame before bpt_target executes
after_bpt
	check #0400, sp
	check #7, r4
	clr @#0177766

	mov #010, r5
	mov #trace_target, @#014
	mov #trace_target, r3
	mov #traced_push, @#0374
	mov #020, @#0376
	mov #0374, sp
	rtt
traced_push
	mov #1, -(sp) ; both TRACE and yellow: TRACE frame must be first
after_traced_push
	check #0376, sp
	check #1, (sp)
	check #010, r4
	clr @#0177766

	; Supervisor/user stacks are not subject to the kernel boundary.
	mov #011, r5
	mov #0140000, @#0177776
	mov #0400, sp
	mov #0777, -(sp)
	check #0376, sp
	check #0, @#0177766
	mov #040000, @#0177776
	mov #0400, sp
	mov #0777, -(sp)
	check #0376, sp
	check #0, @#0177766
	clr @#0177776
	mov #010000, sp

	; First vector push aborts on an odd KSP: RED | ADR, emergency frame 0/2.
	mov #012, r5
	mov #after_red_odd, r3
	mov #010001, sp
	mov #3, @#0177776
	bpt
after_red_odd
	mov #010000, sp
	check #0104, @#0177766
	clr @#0177766

	; A user BPT switches to KSP. First push at PIRQ succeeds; second at
	; unmapped 177770 fails. RED must retain the ORIGINAL user PC/PSW/USP.
	mov #013, r5
	mov #after_red_late, r3
	mov #0177774, sp
	mov #0140003, @#0177776
	mov #012000, sp
	mov #0140003, @#0177776
	bpt
after_red_late
	check #012000, sp
	clr @#0177776
	check #4, sp
	mov #010000, sp
	check #024, @#0177766
	check #012, r4
	mov #012345, r0
	halt

callee
	rts r2
bpt_target
	rti
trace_target
	bic #020, 2(sp)
	rtt

stack_fault
	inc r4
	cmp r5, #012
	bge red_fault
	check #010, @#0177766
	check r3, (sp)
	cmp #1, r5
	bne stack_not_word
	check #1, 2(sp)
stack_not_word
	cmp #010, r5
	bne stack_return
	check #0366, sp
	check #0340, 2(sp)
	check #after_traced_push, 4(sp)
	check #020, 6(sp)
	check #1, 010(sp)
stack_return
	rti
red_fault
	check #0, sp
	check r3, @#0
	cmp #012, r5
	bne red_late
	check #3, @#2
	check #0104, @#0177766
	br red_return
red_late
	check #0140003, @#2
	check #024, @#0177766
red_return
	clr @#0177772 ; first late push deliberately hit PIRQ
	rti
failed
	clr @#0177776
	mov r5, r0
	halt

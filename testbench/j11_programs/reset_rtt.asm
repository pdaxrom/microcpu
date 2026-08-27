	cpu dcj-11
	org 0

	br start

	org 014
	dw trace_handler
	dw 0340

	org 0100
trace_handler
	cmp #1, r1
	bne trace_failed
	mov #012345, r0
	bic #020, 2(sp)		; prevent another trace after RTI
	rti

trace_failed
	clr r0
	bic #020, 2(sp)
	rti

	org 0200
start
	mov #02000, sp
	scc
	reset
	bpl reset_failed
	bne reset_failed
	bvc reset_failed
	bcc reset_failed
	clr r0
	clr r1
	mov #after_rtt, (sp)
	mov #020, 2(sp)		; restore PSW with T set
	rtt

after_rtt
	inc r1			; RTT must allow exactly this instruction first
	halt

reset_failed
	clr r0
	halt

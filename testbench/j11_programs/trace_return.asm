	cpu dcj-11
	org 0

	br start

	org 014
	dw trace_handler
	dw 0

	org 0100
start
	mov #04000, sp
	clr r1			; trace count
	clr r2			; instructions executed after the returns
	mov #after_rti, (sp)
	mov #020, 2(sp)
	rti			; restored T must trace before the next instruction

after_rti
	inc r2
	cmp #1, r1
	bne fail
	cmp #1, r2
	bne fail

	mov #04000, sp
	mov #after_rtt, (sp)
	mov #020, 2(sp)
	rtt			; restored T must allow exactly one instruction

after_rtt
	inc r2
after_rtt_one
	cmp #2, r1
	bne fail
	cmp #2, r2
	bne fail
	mov #012345, r0
	halt

fail
	clr r0
	halt

	org 0600
trace_handler
	inc r1
	cmp #1, r1
	beq check_rti
	cmp #2, r1
	bne handler_failed
	cmp #after_rtt_one, (sp)
	bne handler_failed
	cmp #2, r2
	bne handler_failed
	br handler_return

check_rti
	cmp #after_rti, (sp)
	bne handler_failed
	tst r2
	bne handler_failed

handler_return
	bit #020, 2(sp)
	beq handler_failed
	bic #020, 2(sp)		; leave tracing disabled on the handler return
	rti

handler_failed
	mov #fail, (sp)
	bic #020, 2(sp)
	rti

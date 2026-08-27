	cpu dcj-11
	org 0

	br start

	org 4
	dw halt_handler		; vector 004: non-kernel HALT
	dw 0

	org 020
start
	clr r0
	mov #user_frame, sp
	rti			; enter user mode at priority 2

user_entry
	spl 7			; non-kernel SPL must be a NOP
	mfps r2
	cmp #0100, r2
	bne fail

	mtps #0340		; non-kernel MTPS must preserve IPL
	mfps r3
	cmp #0100, r3
	bne fail

	reset			; non-kernel RESET must not pulse guest_reset

	; A user RTI cannot clear CM or change IPL.
	mov #03000, sp
	mov #after_user_rti, (sp)
	clr 2(sp)
	rti

after_user_rti
	spl 7
	mfps r4
	cmp #0100, r4
	bne fail

	halt			; non-kernel HALT must enter vector 004

after_user_halt
	cmp #1, r0
	bne fail
	spl 6			; reserved CM=2 follows kernel privilege rules
	mfps r2
	bic #0177437, r2
	cmp #0300, r2
	bne fail
	reset
	mov #012345, r0
	halt			; CM=2 is normalized as kernel

fail
	clr r0
	halt

halt_handler
	inc r0
	mov 2(sp), r1
	bic #0037777, r1	; trap frame must contain the old user CM
	cmp #0140000, r1
	bne halt_handler_fail

	spl 3			; the vector itself must run in kernel mode
	mfps r5
	bic #0177437, r5
	cmp #0140, r5
	bne halt_handler_fail

	bic #0140000, 2(sp)
	bis #0100000, 2(sp)	; return through reserved CM=2
	rti

halt_handler_fail
	clr r0
	mov #fail, (sp)
	bic #0140000, 2(sp)
	rti

	; The outgoing kernel SP becomes the inactive KSP after RTI. Keep its
	; frame above the fixed 0400 stack boundary for the later HALT trap.
	org 0600
user_frame
	dw user_entry
	dw 0140100		; user CM, kernel PM, priority 2

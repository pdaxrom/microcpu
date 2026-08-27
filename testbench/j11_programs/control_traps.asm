	cpu dcj-11
	org 0

	br start
	dw 0
	dw 0
	dw 0
	dw jsr_handler		; vector 010: reserved instruction
	dw 0

	org 020
start
	mov #02000, sp
	clr r0

	; DCJ11 sends register-direct JSR to vector 010 without changing the link.
	mov #065432, r5
	mov #012345, r2
	jsr r5, r2
after_bad_jsr
	cmp #2, r0
	bne fail
	cmp #065432, r5
	bne fail
	cmp #02000, sp
	bne fail

	mov #012345, r0
	halt

fail
	clr r0
	halt

jsr_handler
	bis #2, r0
	rti

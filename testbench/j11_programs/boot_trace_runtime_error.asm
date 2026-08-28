; Boot solely from the simulated SD. After real guest UART TX has silenced
; progress, inject a CRC failure on the read or a rejected write data token.
	cpu dcj-11
	org 0
	br start
	org 010
	dw fis_unavailable
	dw 0
	org 0200
start
	tstb @#0177564
	bpl start
	movb #'U', @#0177566
	clr r3
	fadd r0                 ; trace build must trap, not execute FIS
	cmp #1, r3
	bne failed
	mov #1, r2
	mov #-1, @#0177442
	mov #04000, @#0177444
	clr @#0177446
	mov #021, @#0177440
	tst @#0177440
	bmi expected_error
	mov #2, r2
	mov #-1, @#0177442
	mov #04000, @#0177444
	mov #2, @#0177446
	mov #023, @#0177440
	tst @#0177440
	bpl failed
expected_error
	cmp #020000, @#0177454   ; ER1 transport failure, not silent success
	bne failed
	mov #012345, r0
	halt
failed
	mov #077777, r0
	halt
fis_unavailable
	inc r3
	rti
	org 01776
	dw 012345

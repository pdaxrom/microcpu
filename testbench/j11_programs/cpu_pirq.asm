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
	org 064
	dw uart_irq
	dw 0200
	org 0100
	dw clock_irq
	dw 0300
	org 0240
	dw pir_irq
	dw 0340
	org 01000
start
	mov #010000, sp
	mov #1, r5
	clr r1
	clr r2
	clr r3
	spl 7
	mov #010000, @#0177772 ; PIR4 wins a tie with UART BR4
	mov #0100, @#0177564
	spl 4
	check #0, r1
	check #0, r2
	spl 0
	check #2, r1 ; acknowledge must not clear PIRQ: deliberately retrigger once
	check #1, r2
	check #0, @#0177772
	clr @#0177564

	mov #2, r5
	clr r1
	clr r2
	clr r3
	spl 7
	mov #04000, @#0177772 ; PIR3 must not steal an already-ready BR4
	mov #0100, @#0177564
	spl 0
	check #1, r1
	check #1, r2
	clr @#0177564

	mov #3, r5
	clr r1
	spl 7
	mov #040000, @#0177772 ; EVENT/LTC wins a tie with PIR6
	mov #0300, @#0177546
	spl 0
	check #1, r1
	check #1, r3
	check #0100, @#0177546

	; Re-arm native time through RESET, then PIR7 must beat EVENT/LTC.
	reset
	mov #4, r5
	clr r1
	clr r3
	spl 7
	mov #0100000, @#0177772
	mov #0300, @#0177546
	spl 0
	check #1, r1
	check #1, r3
	mov #012345, r0
	halt

pir_irq
	inc r1
	cmp #1, r5
	bne pir_other
	check #0, r2
	check #010210, @#0177772
	cmp #1, r1
	beq pir_return
	br pir_clear
pir_other
	cmp #2, r5
	bne pir_clock
	check #1, r2
	br pir_clear
pir_clock
	cmp #3, r5
	bne pir_before_clock
	check #1, r3
	br pir_clear
pir_before_clock
	check #0, r3
pir_clear
	clr @#0177772
pir_return
	rti
uart_irq
	inc r2
	cmp #1, r5
	bne uart_before_pir
	check #2, r1
	rti
uart_before_pir
	check #0, r1
	rti
clock_irq
	inc r3
	cmp #3, r5
	bne clock_after_pir
	check #0, r1
	rti
clock_after_pir
	check #1, r1
	rti
failed
	mov r5, r0
	halt

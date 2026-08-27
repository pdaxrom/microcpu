	cpu dcj-11
	macro check
	cmp #1, #2
	beq *+6
	jmp @#failed
	endm
	org 0
	br start
	org 4
	dw bus_fault
	dw 0340
	org 060
	dw receive_irq
	dw 0200
	dw transmit_irq
	dw 0200
	org 0100
	dw clock_irq
	dw 0300
	org 0200
start
	mov #010000, sp
	clr r1
	clr r2
	clr r3
	clr r4
	mov #1, r5
	spl 7
	check #0, @#0177560
	check #0200, @#0177564
	check #0200, @#0177546
	check #0200, @#0177546 ; reading LCM is non-destructive
	clrb @#0177546
	mov #0200, @#0177546 ; a write cannot set LCM
	check #0, @#0177546
	movb #0377, @#0177547
	check #0, @#0177546
	movb #0377, @#0177565
	check #0200, @#0177564
	movb @#0177565, r0
	check #0, r0
	check #0, @#0177566
	mov #0100, @#0177564 ; cancel a masked pending TX request by clearing IE
	clr @#0177564
	spl 0
	nop
	check #0, r2
	spl 7
	mov #0177777, @#0177560 ; only IE survives, RE is self-clearing
	check #0100, @#0177560
	clr @#0177560
	; Invalid word/private-service accesses take vector 4, not a CSR effect.
	mov @#0177561, r0
	mov @#0170000, r0
	mov #0, @#0170006
	mov @#0177774, r0 ; no programmable STKLIM on DCJ11
	check #4, r4
	check #0, @#0177560

	; ODT-style polling with no interrupts, including 8-bit MOVB sign extension.
	mov #2, r5
	mov #4, @#0177564 ; maintenance loopback
	movb #0301, @#0177566
poll_tx
	tstb @#0177564
	bpl poll_tx
poll_rx
	tstb @#0177560
	bpl poll_rx
	movb @#0177563, r0 ; high byte must not consume RBUF
	check #0, r0
	check #0200, @#0177560
	movb @#0177562, r0
	check #0177701, r0
	check #0, @#0177560
	movb #'B', @#0177566
poll_re
	tstb @#0177560
	bpl poll_re
	movb #1, @#0177560
	check #0, @#0177560
	movb #'C', @#0177566
poll_rbuf_write
	tstb @#0177560
	bpl poll_rbuf_write
	clrb @#0177562
	check #0, @#0177560

	; Queue both UART sources while masked. A clock must outrank both.
	mov #0104, @#0177564
	movb #'Z', @#0177566
	mov #0100, @#0177560
poll_both_rx
	tstb @#0177560
	bpl poll_both_rx
poll_both_tx
	tstb @#0177564
	bpl poll_both_tx
	mov #0100, @#0177546
	mov #3, r5 ; testbench now supplies one elapsed clock tick
poll_tick
	cmp #0300, @#0177546
	bne poll_tick
	spl 6
	check #0, r3 ; equal IPL masks BR6
	check #0300, @#0177546
	spl 5
	check #1, r3
	check #0, r1
	check #0, r2
	check #0, @#0177546
	spl 3
	check #1, r1
	check #1, r2
	mov #4, r5
	mov #010, r0
no_retrigger
	nop
	sob r0, no_retrigger
	check #1, r1 ; ACK clears request, not DONE: no interrupt storm
	check #1, r2
	check #0300, @#0177560
	check #0304, @#0177564
	clr @#0177560
	mov #0100, @#0177560 ; IE rising with DONE re-arms RX
	check #2, r1
	mov #4, @#0177564
	mov #0104, @#0177564
	check #2, r2
	clr @#0177560
	clr @#0177564
	clr @#0177562

	; A wrapped native tick count must wake WAIT, without fetching past it.
	spl 5
	mov #0100, @#0177546
	mov #5, r5
	wait
	check #2, r3
	check #0, @#0177546
	mov #0100, @#0177546
	mov #6, r5
	wait
	check #3, r3

	; RESET restores guest CSRs and leaves condition codes unchanged.
	spl 7
	mov #0100, @#0177564
	mov #0100, @#0177560
	mov #0100, @#0177546
	scc
	reset
	mfps r0
	bic #0177760, r0
	check #017, r0
	check #0, @#0177560
	check #0200, @#0177564
	check #0200, @#0177546
	mov #012345, r0
	halt

bus_fault
	inc r4
	rti
receive_irq
	inc r1
	cmp #1, r1
	bne receive_return
	check #0, r2 ; RX wins the BR4 tie
receive_return
	rti
transmit_irq
	inc r2
	rti
clock_irq
	check #0100, @#0177546 ; acknowledge has already cleared LCM
	clr @#0177546
	inc r3
	rti
failed
	mov r5, r0
	halt

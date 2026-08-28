; This program is a DISK boot block, never deposited in guest FRAM.
; microasm11 assembles both sectors, including a marker in the second one.
	cpu dcj-11
	macro check
	cmp #1, #2
	beq *+6
	jmp @#failed
	endm
	org 0
	br start
	org 0100
	dw clock_irq
	dw 0300
	org 0200
start
	check #0, r0
	check #0177440, r1
	check #0, r2
	check #0, r3
	check #02020, r4
	check #0, r5
	check #02000, sp
	check #012345, @#01776
	; RESET must preserve RAM and boot ABI registers, not restart SD boot.
	mov #067770, @#01776
	reset
	check #067770, @#01776
	check #02020, r4
	check #0200, @#0177440
	check #0, @#0177442
	; Real elapsed ticks must wake WAIT through vector 100 / BR6 twice.
	clr r3
	spl 5
	mov #0100, @#0177546
	wait
	check #1, r3
	mov #0100, @#0177546
	wait
	check #2, r3
	ifdef UART_TEST
	; The board-level test receives 'U' on tx and sends 'Z' back on rx.
uart_transmit
	tstb @#0177564
	bpl uart_transmit
	movb #'U', @#0177566
uart_receive
	tstb @#0177560
	bpl uart_receive
	movb @#0177562, r2
	check #'Z', r2
	endif
	mov #012345, r0
	halt
clock_irq
	check #0100, @#0177546
	clr @#0177546
	inc r3
	rti
failed
	mov #077777, r0
	halt
	org 01776
	dw 012345

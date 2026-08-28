; Guest access must never reach the microengine's private raw services.
; Run on the real SD/FRAM bus as well as the no-disk ucode profile.
	cpu dcj-11
	macro check
	cmp #1, #2
	beq *+6
	jmp @#failed
	endm
	org 0
	jmp @#start
	org 4
	dw bus_fault, 0340
	org 01000
start
	mov #010000, sp
	spl 7
	clr r4
	mov #020, @#expected_error ; CPUERR.TMO for aligned/private I/O
	mov #1, r5               ; arms the testbench after native initialization
	mov #0170000, r1         ; hex F000..F00F, including both byte lanes
	mov #010, r2
private_even
	jsr pc, word_probe
	jsr pc, byte_probe
	add #2, r1
	sob r2, private_even
	check #070, r4           ; 8 * (3 word/fetch + 4 byte) = 56 faults

	mov #2, r5
	mov #0100, @#expected_error ; odd words retain ADR priority over TMO
	mov #0170001, r1
	mov #010, r2
private_odd
	jsr pc, word_probe
	add #2, r1
	sob r2, private_odd
	check #0120, r4          ; 56 + 8 * 3 = 80

	; Widening the private-window mask must NOT widen the DL11 decode.
	mov #3, r5
	mov #020, @#expected_error
	mov #0177570, r1         ; hex FF78..FF7F is not a second DL11
	mov #4, r2
console_neighbours
	jsr pc, word_probe
	jsr pc, byte_probe
	add #2, r1
	sob r2, console_neighbours
	check #0154, r4          ; 80 + 4 * 7 = 108

	; Real DL11 CSRs still work, with no transmit or receive side effects.
	mov #4, r5
	check #0, @#0177560
	check #0200, @#0177564
	movb #0100, @#0177560
	check #0100, @#0177560
	movb #0377, @#0177561
	check #0100, @#0177560
	clrb @#0177560
	movb #0100, @#0177564
	check #0300, @#0177564
	movb #0377, @#0177565
	check #0300, @#0177564
	clrb @#0177564
	check #0200, @#0177564
	check #0154, r4
	mov #012345, r0
	halt

word_probe
	clr @#0177766
	mov #0125253, r0          ; bit 0 set: a leaked F00C write selects bank 1
	mov #word_read_done, r3
	mov (r1), r0
word_read_done
	check @#expected_error, @#0177766
	check #0125253, r0
	clr @#0177766
	mov #word_write_done, r3
	mov r0, (r1)
word_write_done
	check @#expected_error, @#0177766
	clr @#0177766
	mov #fetch_done, r3
	jmp (r1)
fetch_done
	check @#expected_error, @#0177766
	rts pc

byte_probe
	clr @#0177766
	mov #0125253, r0
	mov #low_read_done, r3
	movb (r1), r0
low_read_done
	check #020, @#0177766
	check #0125253, r0
	clr @#0177766
	mov #low_write_done, r3
	movb r0, (r1)
low_write_done
	check #020, @#0177766
	clr @#0177766
	mov #high_read_done, r3
	movb 1(r1), r0
high_read_done
	check #020, @#0177766
	check #0125253, r0
	clr @#0177766
	mov #high_write_done, r3
	movb r0, 1(r1)
high_write_done
	check #020, @#0177766
	rts pc

bus_fault
	inc r4
	mov r3, (sp)            ; fetch aborts must resume back in guest RAM
	rti
failed
	halt
expected_error
	dw 0

	cpu dcj-11
	macro check
	cmp #1, #2
	beq *+6
	jmp @#failed
	endm
	org 0
	jmp @#start
	org 4
	dw illegal_halt
	dw 0340
	org 014
	dw traced
	dw 0340
	org 01000
start
	mov #010000, sp
	mov #1, r5
	mov #010, @#0177776
	mfps r0
	check #010, r0 ; MOV's NZV must not replace explicitly written CC
	clr @#0177776
	mfps r0
	check #0, r0 ; CLR must not set Z on an explicit PSW write
	movb #013, @#0177776
	mfps r0
	check #013, r0
	mov #7, @#0177776
	bic #4, @#0177776
	mfps r0
	check #3, r0
	mov #2, @#0177776
	add #2, @#0177776
	mfps r0
	check #4, r0
	mov #017, @#0177776
	sub #6, @#0177776
	mfps r0
	check #011, r0
	mov #020, @#0177776
	mfps r0
	check #0, r0 ; explicit write cannot set T

	; No MMU: explicit writes are not MTPS, and can select K/S/U SP banks.
	mov #2, r5
	movb #0100, @#0177777
	mov #012000, sp
	mov #0140000, @#0177776
	mov #014000, sp
	movb #0, @#0177777
	check #010000, sp
	mov #0140000, @#0177776
	check #014000, sp
	movb #0100, @#0177777
	check #012000, sp
	mov #0100000, @#0177776 ; CM=2 uses the kernel SP
	check #010000, sp
	clr @#0177776
	check #010000, sp

	; Non-kernel HALT sets CPUERR.HALT and pushes a frame on saved KSP.
	mov #3, r5
	mov #0140000, @#0177776
	halt
after_halt
	check #014000, sp
	clr @#0177776
	check #010000, sp
	check #0200, @#0177766
	clr @#0177766

	; RTT supplies T without immediate trace; an explicit PSW write keeps T.
	mov #4, r5
	clr r4
	mov #020, -(sp)
	mov #trace_write, -(sp)
	rtt
trace_write
	mov #011, @#0177776
after_trace
	check #1, r4
	check #010000, sp
	mov #012345, r0
	halt

illegal_halt
	check #3, r5
	check #07774, sp
	check #after_halt, (sp)
	check #0140000, 2(sp)
	rti
traced
	check #4, r5
	check #after_trace, (sp)
	check #031, 2(sp)
	bic #020, 2(sp)
	inc r4
	rtt
failed
	clr @#0177776
	mov r5, r0
	halt

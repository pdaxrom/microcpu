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
	org 014
	dw bank1_trap
	dw 04340
	org 020
	dw bank0_nested
	dw 0340
	org 0240
	dw bank1_irq
	dw 04340
	org 01000
start
	mov #010000, sp
	mov #0100, r0
	mov #0101, r1
	mov #0102, r2
	mov #0103, r3
	mov #0104, r4
	mov #0105, r5
	; High-byte PSW write selects six initially zero alternate registers.
	movb #010, @#0177777
	check #0, r0
	check #0, r1
	check #0, r2
	check #0, r3
	check #0, r4
	check #0, r5
	check #010000, sp
	mov #0200, r0
	mov #0201, r1
	mov #0202, r2
	mov #0203, r3
	mov #0204, r4
	mov #0205, r5
	; Rewriting RS=1 and low-byte writes must not exchange the sets.
	mov #04000, @#0177776
	movb #011, @#0177776
	mfps @#saved_cc
	check #011, @#saved_cc
	check #0200, r0
	check #0205, r5
	clr @#0177776
	check #0100, r0
	check #0101, r1
	check #0102, r2
	check #0103, r3
	check #0104, r4
	check #0105, r5
	; RMW writes and MOVB operate on the selected set only.
	bis #04000, @#0177776
	movb #0200, r1
	check #0177600, r1
	bic #04000, @#0177776
	check #0101, r1
	; Destination auto-increment belongs to the outgoing set, before PSW changes.
	mov #0177776, r2
	mov #04000, (r2)+
	check #0202, r2
	clr @#0177776
	check #0, r2
	mov #0102, r2
	; Previous-mode moves use current R0..R5, even when PM differs from CM.
	mov #034000, @#0177776
	mfpi r0
	check #0200, (sp)+
	mov #0333, -(sp)
	mtpd r3
	check #0333, r3
	; Mode/SP changes do not choose the general register set.
	mov #044000, @#0177776
	mov #012000, sp
	check #0200, r0
	mov #04000, @#0177776
	check #010000, sp
	check #0333, r3
	clr @#0177776
	bpt
after_bpt
	check #0100, r0
	check #0776, r1
	check #0102, r2
	check #0103, r3
	check #0104, r4
	check #0105, r5
	check #010000, sp
	check #2, @#trap_count
	; A maskable interrupt also selects the vector's RS and RTI restores it.
	mov #01000, @#0177772
after_irq
	check #1, @#irq_count
	check #0100, r0
	check #010000, sp
	; Outside kernel RTI/RTT can set RS, but cannot clear it.
	mov #0144000, @#0177776
	mov #014000, sp
	mov #0140000, -(sp)
	mov #user_cannot_clear, -(sp)
	rti
user_cannot_clear
	check #01000, r0
	check #014000, sp
	mov #0140000, @#0177776
	check #0100, r0
	mov #0144000, -(sp)
	mov #user_can_set, -(sp)
	rtt
user_can_set
	check #01000, r0
	check #014000, sp
	mov #04000, @#0177776
	check #010000, sp
	; EIS register pairs must refer to the selected set, too.
	mov #2, r0
	mul #3, r0
	check #0, r0
	check #6, r1
	clr @#0177776
	check #0100, r0
	check #0776, r1
	mov #012345, r0
	halt

bank1_trap
	check #0200, r0
	check #0177600, r1
	check #0202, r2
	check #0333, r3
	check #0204, r4
	check #0205, r5
	check #07774, sp
	check #after_bpt, (sp)
	check #0, 2(sp)
	inc @#trap_count
	mov #0777, r0
	iot
after_nested
	check #0777, r0
	check #07774, sp
	rtt
bank0_nested
	check #0100, r0
	check #0101, r1
	check #0102, r2
	check #07770, sp
	check #after_nested, (sp)
	bit #04000, 2(sp)
	beq failed
	mov #0776, r1
	inc @#trap_count
	rti
bank1_irq
	check #0777, r0
	check #after_irq, (sp)
	clr @#0177772
	inc r0
	inc @#irq_count
	rti
failed
	clr @#0177776
	mov #0177777, r0
	halt
saved_cc
	dw 0
trap_count
	dw 0
irq_count
	dw 0

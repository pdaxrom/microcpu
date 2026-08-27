	; The bench injects physical bus faults on read 06000 and write 000002.
	; No guest state or microcode state is injected.
	cpu dcj-11
	macro check
	cmp #1, #2
	beq *+6
	jmp @#failed
	endm
	org 0
	jmp @#start
	org 4
	dw bus_fault
	dw 0340
	org 014
	dw failed
	dw 0340
	org 01000
start
	mov #010000, sp
	mov #1, r5
	clr r4
	mov @#06000, r1
after_read
	check #1, r4
	check #040, @#0177766
	clr @#0177766

	; Abort on an odd, below-limit KSP; then fail the emergency write to 2.
	; Must enter bounded double-abort stop (cause 4), never recurse forever.
	mov #2, r5
	mov #012345, r0
	mov #3, sp
	bpt
failed
	mov r5, r0
	halt
bus_fault
	check #1, r5
	check #after_read, (sp)
	check #040, @#0177766
	inc r4
	rti

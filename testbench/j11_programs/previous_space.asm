	cpu dcj-11
	org 0

start
	; MFPI pushes a register value and updates N/Z/V while preserving C.
	mov #04000, sp
	mov #0100000, r2
	scc
	mfpi r2
	bpl fail
	beq fail
	bvs fail
	bcc fail
	cmp #03776, sp
	bne fail
	cmp #0100000, (sp)
	bne fail

	; MFPD uses the same unified no-MMU space and applies EA side effects once.
	mov #source_word, r3
	sec
	mfpd (r3)+
	bmi fail
	beq fail
	bvs fail
	bcc fail
	cmp #01002, r3
	bne fail
	cmp #012345, (sp)
	bne fail
	cmp #03774, sp
	bne fail

	; Register-direct SP is sampled before the push decrements it.
	mov #04000, sp
	mfpi sp
	cmp #03776, sp
	bne fail
	cmp #04000, (sp)
	bne fail

	; MTPI pops after resolving its register destination.
	mov #05000, sp
	mov #0100000, (sp)
	sec
	mtpi r2
	bpl fail
	beq fail
	bvs fail
	bcc fail
	cmp #0100000, r2
	bne fail
	cmp #05002, sp
	bne fail

	; MTPD resolves and increments the destination before popping the stack.
	mov #05000, sp
	mov #012345, (sp)
	mov #target_word, r3
	sec
	mtpd (r3)+
	bmi fail
	beq fail
	bvs fail
	bcc fail
	cmp #01004, r3
	bne fail
	cmp #012345, target_word
	bne fail
	cmp #05002, sp
	bne fail

	; MTPI SP applies the popped value after the normal pop increment.
	mov #05000, sp
	mov #012345, (sp)
	mtpi sp
	cmp #012345, sp
	bne fail

	; A register-direct PC destination redirects the next instruction fetch.
	mov #05000, sp
	mov #pc_target, (sp)
	mtpi pc
	br fail

pc_target
	mov #012345, r0
	halt

fail
	clr r0
	halt

	org 01000
source_word
	dw 012345
target_word
	dw 0

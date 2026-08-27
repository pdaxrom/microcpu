	cpu dcj-11
	org 0

start
	; NN=0: the saved R5 word immediately follows MARK.
	mov #04000, sp
	mov #mark_zero_target, r5
	scc
	mark 0
mark_zero_saved_r5
	dw 012345

mark_zero_target
	bpl fail_zero
	bne fail_zero
	bvc fail_zero
	bcc fail_zero
	cmp #mark_zero_saved_r5+2, sp
	bne fail_zero
	cmp #012345, r5
	bne fail_zero
	br mark_max_start

fail_zero
	clr r0
	halt

mark_max_start
	; NN=63 (077 octal): skip exactly 126 bytes before popping R5.
	mov #05000, sp
	mov #mark_max_target, r5
	ccc
	mark 077
mark_max_inline
	org mark_max_inline+0176
mark_max_saved_r5
	dw 065432

mark_max_target
	bmi fail_max
	beq fail_max
	bvs fail_max
	bcs fail_max
	cmp #mark_max_saved_r5+2, sp
	bne fail_max
	cmp #065432, r5
	bne fail_max
	mov #012345, r0
	halt

fail_max
	clr r0
	halt

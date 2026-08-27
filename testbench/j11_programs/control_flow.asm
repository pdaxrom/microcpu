	cpu dcj-11
	org 0

	mov #02000, sp

	; JMP uses the resolved address and still applies mode-2 side effects.
	mov #jump_indirect, r1
	jmp (r1)
	br fail

jump_indirect
	mov #jump_auto, r2
	jmp (r2)+
	br fail

jump_auto
	cmp #jump_auto+2, r2
	bne fail

	; Ordinary JSR/RTS saves and restores the link register and stack.
	mov #012345, r5
	jsr r5, subroutine
subroutine_return
	cmp #012345, r5
	bne fail
	cmp #02000, sp
	bne fail
	cmp #065432, r3
	bne fail

	; The DCJ11 samples a same-register link after destination EA effects.
	mov #same_reg_pointer, r2
	jsr r2, @(r2)+
same_reg_return
	cmp #same_reg_pointer+2, r2
	bne fail

	; JSR PC samples PC after its destination extension; RTS PC pops the link.
	jsr pc, pc_subroutine
pc_return
	cmp #076543, r4
	bne fail

	; RTS SP jumps to the old SP and replaces SP with the exact stack word.
	mov #rts_sp_target, sp
	rts sp
	br fail

rts_sp_target
	nop
	cmp #000240, sp
	bne fail
	mov #02000, sp
	mov #012345, r0
	halt

subroutine
	mov (sp), r4
	cmp #012345, r4
	bne fail
	mov #065432, r3
	rts r5

same_reg_subroutine
	mov (sp), r4
	cmp #same_reg_pointer+2, r4
	bne fail
	rts r2

pc_subroutine
	mov (sp), r4
	cmp #pc_return, r4
	bne fail
	mov #076543, r4
	rts pc

fail
	clr r0
	halt

	even
same_reg_pointer
	dw same_reg_subroutine

	cpu dcj-11
	org 0

	mov #01700, sp
	clr r0

	; DCJ11 resolves a non-register destination before sampling a
	; register-direct source. The destination side effect is therefore visible
	; in the value written or compared by all of these instructions.
	mov #02000, r1
	mov r1, (r1)+

	mov #02100, r1
	mov #02200, (r1)
	mov r1, @(r1)+

	mov #02302, r1
	mov r1, -(r1)

	mov #02402, r1
	mov #02500, @#02400
	mov r1, @-(r1)

	mov #02600, r2
	mov pc, 0(r2)
after_mov_pc
	cmp #after_mov_pc, (r2)
	bne fail

	mov #03000, r1
	clrb (r1)
	movb r1, (r1)+

	mov #03200, r1
	mov #03202, (r1)
	cmp r1, (r1)+
	bne fail

	mov #03400, r1
	movb #1, (r1)
	cmpb r1, (r1)+
	bne fail

	mov #01000, r1
	mov #2, (r1)
	bit r1, (r1)+
	beq fail

	mov #03600, r1
	movb #1, (r1)
	bitb r1, (r1)+
	beq fail

	mov #01000, r1
	mov #02000, (r1)
	sub r1, (r1)+

	mov #04000, r1
	mov #1, (r1)
	add r1, (r1)+

	mov #012345, r0
	halt

fail
	halt

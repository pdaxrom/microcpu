	cpu dcj-11
	org 0

start
	mov #04000, sp

	; Small positive product and complete NZVC replacement.
	mov #2, r4
	scc
	mul #3, r4
	bmi fail
	beq fail
	bvs fail
	bcs fail
	cmp #0, r4
	bne fail
	cmp #6, r5
	bne fail

	; Signed negative result still fits in one signed word.
	mov #0177777, r4
	mul #2, r4
	bpl fail
	beq fail
	bvs fail
	bcs fail
	cmp #0177777, r4
	bne fail
	cmp #0177776, r5
	bne fail

	; Positive product outside the signed-word range sets C, not V.
	mov #077777, r4
	mul #2, r4
	bmi fail
	beq fail
	bvs fail
	bcc fail
	cmp #0, r4
	bne fail
	cmp #0177776, r5
	bne fail

	; Zero is tested across both product words.
	clr r4
	mul #0177777, r4
	bmi fail
	bne fail
	bvs fail
	bcs fail
	cmp #0, r4
	bne fail
	cmp #0, r5
	bne fail

	; -32768 is the negative signed-word boundary and must not set C.
	mov #0100000, r4
	mul #1, r4
	bpl fail
	beq fail
	bvs fail
	bcs fail
	cmp #0177777, r4
	bne fail
	cmp #0100000, r5
	bne fail

	; Largest positive operands exercise every shift-add bit.
	mov #077777, r4
	mul #077777, r4
	bmi fail
	beq fail
	bvs fail
	bcc fail
	cmp #037777, r4
	bne fail
	cmp #1, r5
	bne fail

	; Odd R writes its low word over the high word, but flags still use 32 bits.
	mov #0400, r3
	mov #0400, r2
	mul r2, r3
	bmi fail
	beq fail
	bvs fail
	bcc fail
	cmp #0, r3
	bne fail

	; The R operand is sampled before an EA side effect on the same register.
	mov #data_word, r4
	mul (r4)+, r4
	bmi fail
	beq fail
	bvs fail
	bcs fail
	cmp #0, r4
	bne fail
	cmp #02000, r5
	bne fail

	mov #012345, r0
	halt

fail
	clr r0
	halt

	org 01000
data_word
	dw 2

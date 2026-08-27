	cpu dcj-11
	org 0

start
	mov #04000, sp

	; Positive quotient and remainder.
	clr r4
	mov #0144, r5
	scc
	div #7, r4
	bmi fail
	beq fail
	bvs fail
	bcs fail
	cmp #016, r4
	bne fail
	cmp #2, r5
	bne fail

	; A negative dividend produces a negative quotient and remainder.
	mov #0177777, r4
	mov #0177634, r5
	div #7, r4
	bpl fail
	beq fail
	bvs fail
	bcs fail
	cmp #0177762, r4
	bne fail
	cmp #0177776, r5
	bne fail

	; A negative divisor changes only the quotient sign.
	clr r4
	mov #0144, r5
	div #0177771, r4
	bpl fail
	beq fail
	bvs fail
	bcs fail
	cmp #0177762, r4
	bne fail
	cmp #2, r5
	bne fail

	; Two negative operands restore a positive quotient; remainder stays negative.
	mov #0177777, r4
	mov #0177634, r5
	div #0177771, r4
	bmi fail
	beq fail
	bvs fail
	bcs fail
	cmp #016, r4
	bne fail
	cmp #0177776, r5
	bne fail

	; The signed -32768 quotient boundary is valid.
	mov #0177777, r4
	mov #0100000, r5
	div #1, r4
	bpl fail
	beq fail
	bvs fail
	bcs fail
	cmp #0100000, r4
	bne fail
	cmp #0, r5
	bne fail
	br div_tests_continue

fail
	clr r0
	halt

div_tests_continue
	; Divide by zero preserves registers and sets V/C; N follows current R.
	mov #0100000, r4
	mov #012345, r5
	div #0, r4
	bpl fail
	beq fail
	bvc fail
	bcc fail
	cmp #0100000, r4
	bne fail
	cmp #012345, r5
	bne fail

	; A zero quotient register selects Z on divide by zero.
	clr r4
	mov #012345, r5
	div #0, r4
	bmi fail
	bne fail
	bvc fail
	bcc fail
	cmp #0, r4
	bne fail
	cmp #012345, r5
	bne fail

	; A quotient outside signed-word range leaves the pair unchanged.
	mov #1, r4
	clr r5
	div #1, r4
	bmi fail
	beq fail
	bvc fail
	bcs fail
	cmp #1, r4
	bne fail
	cmp #0, r5
	bne fail

	; The -2^31 / -1 special case is also an overflow without register writes.
	mov #0100000, r4
	clr r5
	div #0177777, r4
	bmi fail
	beq fail
	bvc fail
	bcs fail
	cmp #0100000, r4
	bne fail
	cmp #0, r5
	bne fail

	; Odd R uses the same word as both dividend halves and writes only quotient.
	mov #1, r3
	div #3, r3
	bmi fail
	beq fail
	bvs fail
	bcs fail
	cmp #052525, r3
	bne fail

	; The dividend pair is sampled before the divisor EA modifies low R|1.
	clr r4
	mov #divisor_word, r5
	div (r5)+, r4
	bmi fail
	beq fail
	bvs fail
	bcs fail
	cmp #0400, r4
	bne fail
	cmp #0, r5
	bne fail

	; The high dividend word is likewise sampled before its own EA side effect.
	mov #large_divisor_word, r4
	clr r5
	div (r4)+, r4
	bpl fail
	beq fail
	bvs fail
	bcs fail
	cmp #0175774, r4
	bne fail
	cmp #0, r5
	bne fail

	; With a zero divisor there is no result write, so the EA increment remains.
	mov #zero_word, r4
	mov #012345, r5
	div (r4)+, r4
	bmi fail
	beq fail
	bvc fail
	bcc fail
	cmp #01006, r4
	bne fail
	cmp #012345, r5
	bne fail

	mov #012345, r0
	halt

	org 01000
divisor_word
	dw 2
large_divisor_word
	dw 0100000
zero_word
	dw 0

	cpu dcj-11
	org 0

start
	mov #04000, sp

	; Count zero leaves the complete pair unchanged and clears V/C.
	mov #0100000, r4
	mov #1, r5
	scc
	ashc #0, r4
	bpl fail
	beq fail
	bvs fail
	bcs fail
	cmp #0100000, r4
	bne fail
	cmp #1, r5
	bne fail

	; Low-word carry propagates into the high word on a left shift.
	clr r4
	mov #0100000, r5
	ashc #1, r4
	bmi fail
	beq fail
	bvs fail
	bcs fail
	cmp #1, r4
	bne fail
	cmp #0, r5
	bne fail

	; Crossing the pair sign sets V without setting C.
	mov #040000, r4
	clr r5
	ashc #1, r4
	bpl fail
	beq fail
	bvc fail
	bcs fail
	cmp #0100000, r4
	bne fail
	cmp #0, r5
	bne fail

	; Shifting -1 left retains its sign and emits carry.
	mov #0177777, r4
	mov #0177777, r5
	ashc #1, r4
	bpl fail
	beq fail
	bvs fail
	bcc fail
	cmp #0177777, r4
	bne fail
	cmp #0177776, r5
	bne fail

	; A left count of 31 reaches the high sign bit.
	clr r4
	mov #1, r5
	ashc #037, r4
	bpl fail
	beq fail
	bvc fail
	bcs fail
	cmp #0100000, r4
	bne fail
	cmp #0, r5
	bne fail
	br ashc_tests_continue

fail
	clr r0
	halt

ashc_tests_continue

	; 077 is an arithmetic right shift by one across the pair.
	mov #0100000, r4
	mov #1, r5
	ashc #077, r4
	bpl fail
	beq fail
	bvs fail
	bcc fail
	cmp #0140000, r4
	bne fail
	cmp #0, r5
	bne fail

	; 040 is the special arithmetic-right count of 32.
	mov #012345, r4
	mov #067, r5
	ashc #040, r4
	bmi fail
	bne fail
	bvs fail
	bcs fail
	cmp #0, r4
	bne fail
	cmp #0, r5
	bne fail

	mov #0100000, r4
	clr r5
	ashc #040, r4
	bpl fail
	beq fail
	bvs fail
	bcc fail
	cmp #0177777, r4
	bne fail
	cmp #0177777, r5
	bne fail

	; Both pair words are sampled before the count EA modifies low R|1.
	mov #1, r4
	mov #count_word, r5
	ashc (r5)+, r4
	bmi fail
	beq fail
	bvs fail
	bcs fail
	cmp #2, r4
	bne fail
	cmp #02000, r5
	bne fail

	; Odd R writes its low result over the high result, like DCJ11.
	mov #1, r3
	ashc #1, r3
	bmi fail
	beq fail
	bvs fail
	bcs fail
	cmp #2, r3
	bne fail

	mov #012345, r0
	halt

	org 01000
count_word
	dw 1

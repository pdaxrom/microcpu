	cpu dcj-11
	org 0

start
	mov #04000, sp

	; Count zero leaves the word unchanged and clears V/C.
	mov #0100000, r4
	scc
	ash #0, r4
	bpl fail
	beq fail
	bvs fail
	bcs fail
	cmp #0100000, r4
	bne fail

	; A small positive left shift has no exceptional flags.
	mov #1, r4
	ash #1, r4
	bmi fail
	beq fail
	bvs fail
	bcs fail
	cmp #2, r4
	bne fail

	; Crossing the sign bit sets V; the old sign bit supplies C.
	mov #040000, r4
	ash #1, r4
	bpl fail
	beq fail
	bvc fail
	bcs fail
	cmp #0100000, r4
	bne fail

	; A negative value can retain its sign while setting carry.
	mov #0177777, r4
	ash #1, r4
	bpl fail
	beq fail
	bvs fail
	bcc fail
	cmp #0177776, r4
	bne fail

	; Counts 020..037 continue shifting through the 16-bit word.
	mov #1, r4
	ash #020, r4
	bmi fail
	bne fail
	bvc fail
	bcc fail
	cmp #0, r4
	bne fail

	; 077 is an arithmetic right shift by one.
	mov #0100001, r4
	ash #077, r4
	bpl fail
	beq fail
	bvs fail
	bcc fail
	cmp #0140000, r4
	bne fail

	; 040 is the special arithmetic-right count of 32.
	mov #012345, r4
	ash #040, r4
	bmi fail
	bne fail
	bvs fail
	bcs fail
	cmp #0, r4
	bne fail

	mov #0100000, r4
	ash #040, r4
	bpl fail
	beq fail
	bvs fail
	bcc fail
	cmp #0177777, r4
	bne fail

	; R is sampled before the count EA increments the same register.
	mov #count_word, r4
	ash (r4)+, r4
	bmi fail
	beq fail
	bvs fail
	bcs fail
	cmp #02000, r4
	bne fail

	mov #012345, r0
	halt

fail
	clr r0
	halt

	org 01000
count_word
	dw 1

	cpu dcj-11
	org 0

start
	mov #04000, sp

	; Already-locked positive word: old bit 0 sets C and memory stays 1.
	mov #1, lock_word
	scc
	tstset lock_word
	bmi fail
	beq fail
	bvs fail
	bcc fail
	cmp #1, r0
	bne fail
	cmp #1, lock_word
	bne fail

	; Negative already-locked word must also replace a cleared carry.
	mov #0100001, lock_word
	clc
	sev
	tstset lock_word
	bpl fail
	beq fail
	bvs fail
	bcc fail
	cmp #0100001, r0
	bne fail
	cmp #0100001, lock_word
	bne fail

	; WRTLCK zero: set Z, clear N/V, preserve C=0.
	clr r0
	scc
	clz
	clc
	wrtlck lock_word
	bmi fail
	bne fail
	bvs fail
	bcs fail
	cmp #0, lock_word
	bne fail

	; The same zero result must preserve C=1 as well.
	scc
	clz
	wrtlck lock_word
	bmi fail
	bne fail
	bvs fail
	bcc fail
	cmp #0, r0
	bne fail
	cmp #0, lock_word
	bne fail
	br negative_tests

fail
	clr r0
	halt

negative_tests
	; Negative data replaces N/Z/V without introducing a carry.
	mov #0100000, r0
	ccc
	sev
	wrtlck lock_word
	bpl fail
	beq fail
	bvs fail
	bcs fail
	cmp #0100000, lock_word
	bne fail
	cmp #0100000, r0
	bne fail

	; Autodecrement is word-sized and occurs once; incoming C=1 survives.
	mov #lock_word+2, r3
	ccc
	sec
	sev
	wrtlck -(r3)
	bpl fail
	beq fail
	bvs fail
	bcc fail
	cmp #lock_word, r3
	bne fail
	cmp #0100000, lock_word
	bne fail

	; A TSTSET result in R0 overwrites its earlier address-side increment.
	mov #3, lock_word
	mov #lock_word, r0
	tstset (r0)+
	bmi fail
	beq fail
	bvs fail
	bcc fail
	cmp #3, r0
	bne fail
	cmp #3, lock_word
	bne fail
	mov #012345, r0
	halt

	org 01000
lock_word
	dw 0

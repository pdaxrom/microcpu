	cpu dcj-11
	org 0

	br start
	dw 0
	dw 0
	dw 0
	dw reserved_handler	; vector 010
	dw 0

	org 020
start
	mov #04000, sp
	clr trap_count

	; MARK builds SP from post-fetch PC, jumps through R5, then pops R5.
	mov #mark_target, r5
	scc
	mark 2
mark_inline_0
	dw 011111
mark_inline_1
	dw 022222
mark_saved_r5
	dw 033333

mark_target
	bpl fail
	bne fail
	bvc fail
	bcc fail
	cmp #mark_saved_r5+2, sp
	bne fail
	cmp #033333, r5
	bne fail
	; MARK leaves SP in the inline data below 0400. Restore a normal kernel
	; stack before the later reserved-instruction traps.
	mov #04000, sp

	; TSTSET copies the old word to R0, sets memory bit zero, and replaces NZVC.
	mov #0100000, lock_word
	tstset lock_word
	bpl fail
	beq fail
	bvs fail
	bcs fail
	cmp #0100000, r0
	bne fail
	cmp #0100001, lock_word
	bne fail

	; Zero supplies Z with clear C; autoincrement occurs exactly once.
	clr lock_word
	mov #lock_word, r2
	tstset (r2)+
	bmi fail
	bne fail
	bvs fail
	bcs fail
	cmp #0, r0
	bne fail
	cmp #01002, r2
	bne fail
	cmp #1, lock_word
	bne fail

	; WRTLCK stores R0, updates N/Z/V, and preserves the old carry.
	mov #040000, r0
	sec
	wrtlck write_word
	bmi fail
	beq fail
	bvs fail
	bcc fail
	cmp #040000, write_word
	bne fail

	; R0 is sampled after an EA side effect that modifies R0 itself.
	mov #write_word, r0
	sec
	wrtlck (r0)+
	bmi fail
	beq fail
	bvs fail
	bcc fail
	cmp #01004, write_word
	bne fail

	; Register-direct lock instructions enter reserved vector 010.
	mov #012345, r1
	tstset r1
	cmp #012345, r1
	bne fail
	wrtlck r1
	cmp #2, trap_count
	bne fail

	mov #012345, r0
	halt

fail
	clr r0
	halt

reserved_handler
	inc trap_count
	rti

	org 01000
lock_word
	dw 0
write_word
	dw 0
trap_count
	dw 0

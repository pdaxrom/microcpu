; FIS compatibility extension: FADD, FSUB, FMUL, FDIV (not FP11).
; DEC F-format: sign, excess-128 exponent, 23 stored fraction bits.
; A = 4(Rn), B = (Rn); store A op B at 4(Rn), then Rn += 4.
; Rounding is nearest, with halfway magnitudes rounded away from zero.
; Exponent-zero inputs, including dirty/negative zeros, are clean zero.
; This extension uses correctly rounded F-format arithmetic, not the old
; KE11-F's two-guard-bit/24-place alignment shortcut; see docs/fpga-j11.md.
;
; No new hardware or context words.  During arithmetic only, memory-helper
; scratch is reused: 25=result sign, 26=sign XOR, 27=EA, 28=EB, 29=counter.
; 12 preserves original Rn across memory calls; 13 holds the operation.
; v0:v1 and v2:v3 are unsigned mantissas.  Arithmetic returns v0:v1 with
; the hidden bit at bit 29 and six guard positions; sp is the exponent.
; Memory helpers may be called only before or after this arithmetic phase.
; Keep native v0 = guest PC during EVERY memory call: the bus-abort ABI uses
; it when saving the trap frame. It is arithmetic scratch only between calls.

fis_entry
	and lr, v1, 7
	ggetr sp, lr
	gset sp, 12
	shr lr, v1, 3
	and lr, lr, 3
	gset lr, 13
	readw v2, sp, 0
	readw v3, sp, 2
	readw v4, sp, 4
	readw v1, sp, 6
	mov v0, v4

	; Extract exponents and canonicalize all exponent-zero encodings.
	set v4, $ff
	shr sp, v0, 7
	and sp, sp, v4
	gset sp, 27
	bne fis_a_nonzero, sp, 0
	clr v0
	clr v1
fis_a_nonzero
	shr sp, v2, 7
	and sp, sp, v4
	gset sp, 28
	bne fis_b_nonzero, sp, 0
	clr v2
	clr v3
fis_b_nonzero
	; Subtraction changes B's sign before the common add path.
	gget lr, 13
	bne fis_signs, lr, 1
	set v4, $8000
	xor v2, v2, v4
fis_signs
	gset v0, 25
	xor v4, v0, v2
	gset v4, 26
	set v4, $7f
	and v0, v0, v4
	and v2, v2, v4
	inc v4
	; Hidden bits need not be suppressed: zero paths use the exponents.
	or v0, v0, v4
	or v2, v2, v4
	gget sp, 27
	gget v4, 28
	bgeu fis_mul_div, lr, 2

	; Addition: deal with zeros, then sort by magnitude before subtracting.
	beq fis_add_use_b, sp, 0
	beq fis_add_use_a, v4, 0
	bltu fis_add_swap, sp, v4
	bne fis_add_sorted, sp, v4
	bltu fis_add_swap, v0, v2
	bne fis_add_sorted, v0, v2
	bgeu fis_add_sorted, v1, v3
fis_add_swap
	mov lr, v0
	mov v0, v2
	mov v2, lr
	mov lr, v1
	mov v1, v3
	mov v3, lr
	mov lr, sp
	mov sp, v4
	mov v4, lr
	gget lr, 25
	gget v4, 26
	xor lr, lr, v4
	gset lr, 25
	gget v4, 27		; smaller exponent was the original EA
fis_add_sorted
	sub v4, sp, v4
	gset sp, 27
	gset v4, 29
	; Shift both 24-bit significands left six, keeping six guard bits.
	shr lr, v1, 10
	shl v0, v0, 6
	or v0, v0, lr
	shl v1, v1, 6
	shr lr, v3, 10
	shl v2, v2, 6
	or v2, v2, lr
	shl v3, v3, 6
	set lr, 31
	bgeu fis_add_combine, v4, lr	; tiny B cannot affect rounding
	beq fis_add_aligned, v4, 0
fis_add_align
	; Right shift with jam: retain whether ANY discarded bit was nonzero.
	and lr, v3, 1
	shl sp, v2, 15
	shr v3, v3, 1
	or v3, v3, sp
	or v3, v3, lr
	shr v2, v2, 1
	dec v4
	bne fis_add_align, v4, 0
	b fis_add_aligned
fis_add_combine
	clr v2
	clr v3
fis_add_aligned
	gget sp, 27
	gget v4, 26
	blt fis_subtract, v4, 0
	add v1, v1, v3
	getf lr
	and lr, lr, 1
	add v0, v0, v2
	add v0, v0, lr
	set v4, $4000
	bmask_clear fis_normalize, v0, v4
	bsr fis_shift_right
	inc sp
	b fis_round
fis_subtract
	sub v1, v1, v3
	getf lr
	and lr, lr, 1
	sub v0, v0, v2
	sub v0, v0, lr
	b fis_normalize

fis_add_use_b
	beq fis_zero, v4, 0
	mov v0, v2
	mov v1, v3
	mov sp, v4
	gget lr, 25
	gget v4, 26
	xor lr, lr, v4
	gset lr, 25
fis_add_use_a
	shr lr, v1, 10
	shl v0, v0, 6
	or v0, v0, lr
	shl v1, v1, 6
	b fis_round

fis_mul_div
	; Multiplication/division use sign(A) XOR sign(B).
	gget v4, 26
	gset v4, 25
	gget v4, 28
	beq fis_divide, lr, 3
	beq fis_zero, sp, 0
	beq fis_zero, v4, 0
	add sp, sp, v4
	set lr, 128
	sub sp, sp, lr
	gset sp, 27
	; v2:v3 = B << 6, sp:lr = 24-bit multiplier A.
	mov sp, v0
	mov lr, v1
	shr v4, v3, 10
	shl v2, v2, 6
	or v2, v2, v4
	shl v3, v3, 6
	clr v0
	clr v1
	set v4, 24
	gset v4, 29
fis_multiply_loop
	bmask_clear fis_multiply_shift, lr, 1
	add v1, v1, v3
	getf v4
	and v4, v4, 1
	add v0, v0, v2
	add v0, v0, v4
fis_multiply_shift
	shl v4, v0, 15
	shr v1, v1, 1
	or v1, v1, v4
	shr v0, v0, 1
	shl v4, sp, 15
	shr lr, lr, 1
	or lr, lr, v4
	shr sp, sp, 1
	gget v4, 29
	dec v4
	gset v4, 29
	bne fis_multiply_loop, v4, 0
	gget sp, 27
	b fis_normalize

fis_divide
	beq fis_divide_zero, v4, 0	; 0/0 is a divide-by-zero exception too
	beq fis_zero, sp, 0
	sub sp, sp, v4
	set lr, 129
	add sp, sp, lr
	gset sp, 27
	clr sp
	clr lr
	set v4, 30
	gset v4, 29
fis_divide_loop
	; Generate one integer bit and 29 fractional quotient bits.
	shr v4, lr, 15
	shl sp, sp, 1
	or sp, sp, v4
	shl lr, lr, 1
	bltu fis_divide_next, v0, v2
	bne fis_divide_subtract, v0, v2
	bltu fis_divide_next, v1, v3
fis_divide_subtract
	sub v1, v1, v3
	getf v4
	and v4, v4, 1
	sub v0, v0, v2
	sub v0, v0, v4
	or lr, lr, 1
fis_divide_next
	shr v4, v1, 15
	shl v0, v0, 1
	or v0, v0, v4
	shl v1, v1, 1
	gget v4, 29
	dec v4
	gset v4, 29
	bne fis_divide_loop, v4, 0
	mov v0, sp
	mov v1, lr
	gget sp, 27

fis_normalize
	or v4, v0, v1
	beq fis_zero, v4, 0
	set v4, $2000
fis_normalize_loop
	bmask_set fis_round, v0, v4
	shr lr, v1, 15
	shl v0, v0, 1
	or v0, v0, lr
	shl v1, v1, 1
	dec sp
	b fis_normalize_loop
fis_round
	set v4, $20
	add v1, v1, v4
	getf lr
	and lr, lr, 1
	add v0, v0, lr
	set v4, $4000
	bmask_clear fis_pack, v0, v4
	bsr fis_shift_right
	inc sp
fis_pack
	ble fis_underflow, sp, 0
	set v4, 256
	bgeu fis_overflow, sp, v4
	shl lr, v0, 10
	shr v1, v1, 6
	or v1, v1, lr
	shr v0, v0, 6
	set v4, $7f
	and v0, v0, v4
	shl sp, sp, 7
	or v0, v0, sp
	gget lr, 25
	set v4, $8000
	and lr, lr, v4
	or v0, v0, lr
	shr v2, lr, 12		; NZVC = sign ? N : 0
	b fis_store
fis_zero
	clr v0
	clr v1
	set v2, 4
fis_store
	; Finish scratch-only math before invoking any memory helper.
	gget sp, 12
	add sp, sp, 4
	mov v4, v0
	gget v0, 7
	writew v4, sp, 0
	writew v1, sp, 2
	gget lr, 9
	and lr, lr, 7
	gsetr sp, lr
	bsr fis_set_flags
	far_jump fetch

fis_shift_right
	shl v4, v0, 15
	shr v1, v1, 1
	or v1, v1, v4
	shr v0, v0, 1
	rts

fis_set_flags
	gget v3, 8
	set v4, $fff0
	and v3, v3, v4
	or v3, v3, v2
	; Preserve the return register: pset itself clobbers lr.
	gget v4, 14
	bts v4, 8
	gset v3, 8
	rts

fis_divide_zero
	set v2, 11		; NVC: divide by zero
	b fis_exception
fis_underflow
	set v2, 10		; NV: exponent <= 0 after rounding
	b fis_exception
fis_overflow
	set v2, 2		; V: exponent > 255 after rounding
fis_exception
	; Arithmetic faults leave both operands and Rn untouched. The ordinary
	; mode-aware trap saves full PSW with the FIS condition-code signature.
	bsr fis_set_flags
	gget v0, 7
	set sp, $a4		; octal 0244
	far_jump trap_entry

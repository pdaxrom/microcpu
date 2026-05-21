;
; 32-bit FIS-like floating point support for microcpu.
;
; This include emits procedure code and includes int32.inc internally. Include
; it after the code that calls these routines, or branch around it.
;
; Format (FIS32):
;   v1:v0 is one floating point number.
;   v1 bit 15      - sign
;   v1 bits 14..7  - exponent, biased by 0200 octal / 128 decimal
;   v1 bits 6..0   - fraction bits 22..16
;   v0             - fraction bits 15..0
;
; Value:
;   zero is exponent = 0 and fraction = 0
;   nonzero = (-1)^sign * (0.1fraction) * 2^(exponent - 128)
;
; ABI:
;   lhs/result: v1:v0
;   rhs:        v3:v2
;   v4 is scratch.
;
; Routines:
;   f32add, f32sub, f32mul, f32div
;
; Overflow saturates to exponent 255, fraction all ones. Underflow becomes
; zero. Division by zero returns saturated max with quotient sign. Routines use
; a per-call stack frame and are reentrant.
;

FIS32_BIAS equ 128
FIS32_LRAW_LO equ 2
FIS32_LRAW_HI equ 4
FIS32_RRAW_LO equ 6
FIS32_RRAW_HI equ 8
FIS32_LZERO equ 10
FIS32_RZERO equ 12
FIS32_LSIGN equ 14
FIS32_RSIGN equ 16
FIS32_SIGN equ 18
FIS32_LEXP equ 20
FIS32_REXP equ 22
FIS32_EXP equ 24
FIS32_LMANT_LO equ 26
FIS32_LMANT_HI equ 28
FIS32_RMANT_LO equ 30
FIS32_RMANT_HI equ 32
FIS32_PROD0 equ 34
FIS32_PROD1 equ 36
FIS32_PROD2 equ 38
FIS32_MC0 equ 40
FIS32_MC1 equ 42
FIS32_MC2 equ 44
FIS32_QLO equ 46
FIS32_QHI equ 48
FIS32_OLD0 equ 50
FIS32_OLD1 equ 52
FIS32_CARRY equ 54
FIS32_COUNT equ 56
FIS32_REM_LO equ 58
FIS32_REM_HI equ 60
FIS32_DIV_LO equ 62
FIS32_DIV_HI equ 64
FIS32_QUOT_LO equ 66
FIS32_QUOT_HI equ 68
FIS32_FRAME_SIZE equ 70
FIS32_DIVLOC_COUNT equ 0
FIS32_DIVLOC_QUOT_LO equ 2
FIS32_DIVLOC_QUOT_HI equ 4
FIS32_DIVLOC_REM_LO equ 6
FIS32_DIVLOC_REM_HI equ 8
FIS32_DIVLOC_FRAME_SIZE equ 10

	macro	fis32_addr
	set	#1, #2
	add	#1, sp, #1
	endm

	macro	fis32_addr1
	set	#1, #2 + 2
	add	#1, sp, #1
	endm

	macro	fis32_addr2
	set	#1, #2 + 4
	add	#1, sp, #1
	endm

f32add proc
	set	v4, FIS32_FRAME_SIZE
	sub	sp, sp, v4
	str	lr, sp, 0

	bsr	fis32_unpack_operands

	fis32_addr	v4, FIS32_LZERO
	ldr	v4, v4, 0
	eq	v4, 0
	b	f32add_lhs_zero
	b	f32add_check_rhs_zero

f32add_lhs_zero:
	fis32_addr	v4, FIS32_RRAW_LO
	ldr	v0, v4, 0
	fis32_addr	v4, FIS32_RRAW_HI
	ldr	v1, v4, 0
	b	f32add_done

f32add_check_rhs_zero:
	fis32_addr	v4, FIS32_RZERO
	ldr	v4, v4, 0
	eq	v4, 0
	b	f32add_rhs_zero
	b	f32add_align

f32add_rhs_zero:
	fis32_addr	v4, FIS32_LRAW_LO
	ldr	v0, v4, 0
	fis32_addr	v4, FIS32_LRAW_HI
	ldr	v1, v4, 0
	b	f32add_done

f32add_align:
	fis32_addr	v4, FIS32_LEXP
	ldr	v1, v4, 0
	fis32_addr	v4, FIS32_REXP
	ldr	v3, v4, 0
	ltu	v1, v3
	b	f32add_lhs_exp_ge
	b	f32add_lhs_exp_lt

f32add_lhs_exp_lt:
	sub	v2, v3, v1
	fis32_addr	v4, FIS32_EXP
	str	v3, v4, 0
	fis32_addr	v4, FIS32_LMANT_LO
	ldr	v0, v4, 0
	fis32_addr	v4, FIS32_LMANT_HI
	ldr	v1, v4, 0
	set	v3, 24
	ltu	v2, v3
	b	f32add_lmant_zero
	jsr	u32_shr
	b	f32add_store_lmant
f32add_lmant_zero:
	setl	v0, 0
	seth	v0, 0
	setl	v1, 0
	seth	v1, 0
f32add_store_lmant:
	fis32_addr	v4, FIS32_LMANT_LO
	str	v0, v4, 0
	fis32_addr	v4, FIS32_LMANT_HI
	str	v1, v4, 0
	b	f32add_after_align

f32add_lhs_exp_ge:
	sub	v2, v1, v3
	fis32_addr	v4, FIS32_EXP
	str	v1, v4, 0
	fis32_addr	v4, FIS32_RMANT_LO
	ldr	v0, v4, 0
	fis32_addr	v4, FIS32_RMANT_HI
	ldr	v1, v4, 0
	set	v3, 24
	ltu	v2, v3
	b	f32add_rmant_zero
	jsr	u32_shr
	b	f32add_store_rmant
f32add_rmant_zero:
	setl	v0, 0
	seth	v0, 0
	setl	v1, 0
	seth	v1, 0
f32add_store_rmant:
	fis32_addr	v4, FIS32_RMANT_LO
	str	v0, v4, 0
	fis32_addr	v4, FIS32_RMANT_HI
	str	v1, v4, 0

f32add_after_align:
	fis32_addr	v4, FIS32_LSIGN
	ldr	v0, v4, 0
	fis32_addr	v4, FIS32_RSIGN
	ldr	v1, v4, 0
	eq	v0, v1
	b	f32add_signs_differ
	b	f32add_signs_same

f32add_signs_same:
	fis32_addr	v4, FIS32_LMANT_LO
	ldr	v0, v4, 0
	fis32_addr	v4, FIS32_LMANT_HI
	ldr	v1, v4, 0
	fis32_addr	v4, FIS32_RMANT_LO
	ldr	v2, v4, 0
	fis32_addr	v4, FIS32_RMANT_HI
	ldr	v3, v4, 0
	jsr	u32_add

	set	v4, $0100
	and	v4, v1, v4
	eq	v4, 0
	b	f32add_same_carry
	b	f32add_same_pack

f32add_same_carry:
	jsr	u32_shr1
	fis32_addr	v4, FIS32_EXP
	ldr	v2, v4, 0
	add	v2, v2, 1
	str	v2, v4, 0

f32add_same_pack:
	fis32_addr	v4, FIS32_LSIGN
	ldr	v4, v4, 0
	bsr	fis32_pack
	b	f32add_done

f32add_signs_differ:
	fis32_addr	v4, FIS32_LMANT_LO
	ldr	v0, v4, 0
	fis32_addr	v4, FIS32_LMANT_HI
	ldr	v1, v4, 0
	fis32_addr	v4, FIS32_RMANT_LO
	ldr	v2, v4, 0
	fis32_addr	v4, FIS32_RMANT_HI
	ldr	v3, v4, 0
	bsr	fis32_ge_u32
	eq	v4, 0
	b	f32add_lmant_ge_rmant
	b	f32add_rmant_gt_lmant

f32add_lmant_ge_rmant:
	jsr	u32_sub
	fis32_addr	v4, FIS32_LSIGN
	ldr	v4, v4, 0
	b	f32add_normalize

f32add_rmant_gt_lmant:
	fis32_addr	v4, FIS32_RMANT_LO
	ldr	v0, v4, 0
	fis32_addr	v4, FIS32_RMANT_HI
	ldr	v1, v4, 0
	fis32_addr	v4, FIS32_LMANT_LO
	ldr	v2, v4, 0
	fis32_addr	v4, FIS32_LMANT_HI
	ldr	v3, v4, 0
	jsr	u32_sub
	fis32_addr	v4, FIS32_RSIGN
	ldr	v4, v4, 0

f32add_normalize:
	fis32_addr	v3, FIS32_SIGN
	str	v4, v3, 0
	bsr	fis32_normalize
	fis32_addr	v4, FIS32_SIGN
	ldr	v4, v4, 0
	bsr	fis32_pack

f32add_done:
	ldr	lr, sp, 0
	set	v4, FIS32_FRAME_SIZE
	add	sp, sp, v4
	rts
	endp

f32sub proc
	setl	v4, 0
	seth	v4, $80
	xor	v3, v3, v4
	b	f32add
	endp

f32mul proc
	set	v4, FIS32_FRAME_SIZE
	sub	sp, sp, v4
	str	lr, sp, 0

	bsr	fis32_unpack_operands
	fis32_addr	v4, FIS32_LZERO
	ldr	v4, v4, 0
	eq	v4, 0
	b	f32mul_zero
	fis32_addr	v4, FIS32_RZERO
	ldr	v4, v4, 0
	eq	v4, 0
	b	f32mul_zero

	bsr	fis32_store_result_sign
	fis32_addr	v4, FIS32_LEXP
	ldr	v1, v4, 0
	fis32_addr	v4, FIS32_REXP
	ldr	v0, v4, 0
	add	v1, v1, v0
	set	v0, FIS32_BIAS
	sub	v1, v1, v0
	fis32_addr	v4, FIS32_EXP
	str	v1, v4, 0

	bsr	fis32_mul_mant
	fis32_addr	v4, FIS32_PROD2
	ldr	v4, v4, 0
	ge	v4, 0
	b	f32mul_product_ge_half
	b	f32mul_product_lt_half

f32mul_product_ge_half:
	fis32_addr	v4, FIS32_PROD1
	ldr	v0, v4, 0
	shr	v0, v0, 8
	fis32_addr	v4, FIS32_PROD2
	ldr	v1, v4, 0
	set	v2, $00ff
	mov	v3, v1
	and	v3, v3, v2
	shl	v3, v3, 8
	or	v0, v0, v3
	shr	v1, v1, 8
	and	v1, v1, v2
	b	f32mul_product_done

f32mul_product_lt_half:
	fis32_addr	v4, FIS32_EXP
	ldr	v1, v4, 0
	sub	v1, v1, 1
	str	v1, v4, 0
	fis32_addr	v4, FIS32_PROD1
	ldr	v0, v4, 0
	shr	v0, v0, 7
	fis32_addr	v4, FIS32_PROD2
	ldr	v1, v4, 0
	set	v2, $007f
	mov	v3, v1
	and	v3, v3, v2
	shl	v3, v3, 9
	or	v0, v0, v3
	shr	v1, v1, 7
	set	v2, $00ff
	and	v1, v1, v2
	b	f32mul_product_done

f32mul_product_done:
	fis32_addr	v4, FIS32_SIGN
	ldr	v4, v4, 0
	bsr	fis32_pack
	b	f32mul_done

f32mul_zero:
	setl	v0, 0
	seth	v0, 0
	setl	v1, 0
	seth	v1, 0

f32mul_done:
	ldr	lr, sp, 0
	set	v4, FIS32_FRAME_SIZE
	add	sp, sp, v4
	rts
	endp

f32div proc
	set	v4, FIS32_FRAME_SIZE
	sub	sp, sp, v4
	str	lr, sp, 0

	bsr	fis32_unpack_operands
	fis32_addr	v4, FIS32_LZERO
	ldr	v4, v4, 0
	eq	v4, 0
	b	f32div_zero

	bsr	fis32_store_result_sign
	fis32_addr	v4, FIS32_RZERO
	ldr	v4, v4, 0
	eq	v4, 0
	b	f32div_by_zero

	fis32_addr	v4, FIS32_LEXP
	ldr	v1, v4, 0
	set	v0, FIS32_BIAS
	add	v1, v1, v0
	fis32_addr	v4, FIS32_REXP
	ldr	v0, v4, 0
	sub	v1, v1, v0
	fis32_addr	v4, FIS32_EXP
	str	v1, v4, 0

	bsr	fis32_div_mant
	fis32_addr	v4, FIS32_SIGN
	ldr	v4, v4, 0
	bsr	fis32_pack
	b	f32div_done

f32div_by_zero:
	fis32_addr	v4, FIS32_SIGN
	ldr	v4, v4, 0
	bsr	fis32_overflow_value
	b	f32div_done

f32div_zero:
	setl	v0, 0
	seth	v0, 0
	setl	v1, 0
	seth	v1, 0

f32div_done:
	ldr	lr, sp, 0
	set	v4, FIS32_FRAME_SIZE
	add	sp, sp, v4
	rts
	endp

fis32_unpack_operands proc
	fis32_addr	v4, FIS32_LRAW_LO
	str	v0, v4, 0
	fis32_addr	v4, FIS32_LRAW_HI
	str	v1, v4, 0
	fis32_addr	v4, FIS32_RRAW_LO
	str	v2, v4, 0
	fis32_addr	v4, FIS32_RRAW_HI
	str	v3, v4, 0

	setl	v4, 0
	seth	v4, 0
	fis32_addr	v2, FIS32_LZERO
	str	v4, v2, 0
	fis32_addr	v2, FIS32_RZERO
	str	v4, v2, 0

	ne	v0, 0
	b	fis32_unpack_lzero_check_hi
	b	fis32_unpack_l_nonzero
fis32_unpack_lzero_check_hi:
	set	v4, $7fff
	and	v4, v1, v4
	ne	v4, 0
	b	fis32_unpack_l_is_zero
	b	fis32_unpack_l_nonzero
fis32_unpack_l_is_zero:
	setl	v4, 1
	seth	v4, 0
	fis32_addr	v2, FIS32_LZERO
	str	v4, v2, 0

fis32_unpack_l_nonzero:
	setl	v4, 0
	seth	v4, 0
	ge	v1, 0
	setl	v4, 1
	fis32_addr	v2, FIS32_LSIGN
	str	v4, v2, 0

	mov	v4, v1
	shr	v4, v4, 7
	set	v2, $00ff
	and	v4, v4, v2
	fis32_addr	v2, FIS32_LEXP
	str	v4, v2, 0

	set	v4, $007f
	and	v4, v1, v4
	set	v2, $0080
	or	v4, v4, v2
	fis32_addr	v2, FIS32_LMANT_HI
	str	v4, v2, 0
	fis32_addr	v4, FIS32_LMANT_LO
	str	v0, v4, 0

	fis32_addr	v4, FIS32_RRAW_LO
	ldr	v2, v4, 0
	fis32_addr	v4, FIS32_RRAW_HI
	ldr	v3, v4, 0

	ne	v2, 0
	b	fis32_unpack_rzero_check_hi
	b	fis32_unpack_r_nonzero
fis32_unpack_rzero_check_hi:
	set	v4, $7fff
	and	v4, v3, v4
	ne	v4, 0
	b	fis32_unpack_r_is_zero
	b	fis32_unpack_r_nonzero
fis32_unpack_r_is_zero:
	setl	v4, 1
	seth	v4, 0
	fis32_addr	v2, FIS32_RZERO
	str	v4, v2, 0

fis32_unpack_r_nonzero:
	setl	v4, 0
	seth	v4, 0
	ge	v3, 0
	setl	v4, 1
	fis32_addr	v2, FIS32_RSIGN
	str	v4, v2, 0

	mov	v4, v3
	shr	v4, v4, 7
	set	v2, $00ff
	and	v4, v4, v2
	fis32_addr	v2, FIS32_REXP
	str	v4, v2, 0

	set	v4, $007f
	and	v4, v3, v4
	set	v2, $0080
	or	v4, v4, v2
	fis32_addr	v2, FIS32_RMANT_HI
	str	v4, v2, 0
	fis32_addr	v4, FIS32_RMANT_LO
	fis32_addr	v2, FIS32_RRAW_LO
	ldr	v2, v2, 0
	str	v2, v4, 0
	rts
	endp

fis32_store_result_sign proc
	fis32_addr	v4, FIS32_LSIGN
	ldr	v4, v4, 0
	fis32_addr	v3, FIS32_RSIGN
	ldr	v3, v3, 0
	xor	v4, v4, v3
	fis32_addr	v3, FIS32_SIGN
	str	v4, v3, 0
	rts
	endp

fis32_normalize proc
	sub	sp, sp, 2
	str	lr, sp, 0

	ne	v0, 0
	b	fis32_norm_check_hi
	b	fis32_norm_not_zero
fis32_norm_check_hi:
	ne	v1, 0
	b	fis32_norm_zero
	b	fis32_norm_not_zero

fis32_norm_zero:
	setl	v0, 0
	seth	v0, 0
	setl	v1, 0
	seth	v1, 0
	b	fis32_norm_return

fis32_norm_not_zero:
	set	v4, $0080
	and	v4, v1, v4
	eq	v4, 0
	b	fis32_norm_done
	fis32_addr1	v4, FIS32_EXP
	ldr	v4, v4, 0
	eq	v4, 0
	b	fis32_norm_exp_nonzero
	b	fis32_norm_zero

fis32_norm_exp_nonzero:
	jsr	u32_shl1
	fis32_addr1	v4, FIS32_EXP
	ldr	v3, v4, 0
	sub	v3, v3, 1
	str	v3, v4, 0
	b	fis32_norm_not_zero

fis32_norm_done:
fis32_norm_return:
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

fis32_pack proc
	ne	v0, 0
	b	fis32_pack_check_hi
	b	fis32_pack_nonzero
fis32_pack_check_hi:
	ne	v1, 0
	b	fis32_pack_zero
	b	fis32_pack_nonzero

fis32_pack_zero:
	setl	v0, 0
	seth	v0, 0
	setl	v1, 0
	seth	v1, 0
	rts

fis32_pack_nonzero:
	fis32_addr	v2, FIS32_EXP
	ldr	v2, v2, 0
	ge	v2, 0
	b	fis32_pack_zero
	eq	v2, 0
	b	fis32_pack_exp_nonzero
	b	fis32_pack_zero

fis32_pack_exp_nonzero:
	set	v3, $ff00
	and	v3, v2, v3
	eq	v3, 0
	b	fis32_pack_overflow

	set	v3, $007f
	and	v1, v1, v3
	shl	v2, v2, 7
	or	v1, v1, v2
	eq	v4, 0
	b	fis32_pack_sign
	rts

fis32_pack_sign:
	setl	v2, 0
	seth	v2, $80
	or	v1, v1, v2
	rts

fis32_pack_overflow:
	b	fis32_overflow_value
	endp

fis32_overflow_value proc
	setl	v0, $ff
	seth	v0, $ff
	setl	v1, $ff
	seth	v1, $7f
	eq	v4, 0
	b	fis32_overflow_sign
	rts
fis32_overflow_sign:
	setl	v2, 0
	seth	v2, $80
	or	v1, v1, v2
	rts
	endp

fis32_ge_u32 proc
	setl	v4, 0
	seth	v4, 0
	ltu	v1, v3
	b	fis32_ge_hi_not_lt
	rts
fis32_ge_hi_not_lt:
	ltu	v3, v1
	b	fis32_ge_hi_eq
	setl	v4, 1
	rts
fis32_ge_hi_eq:
	ltu	v0, v2
	b	fis32_ge_true
	rts
fis32_ge_true:
	setl	v4, 1
	rts
	endp

fis32_mul_mant proc
	; 24x24 mantissa multiply as 16x16, 16x8, 8x16, and 8x8 partials.
	sub	sp, sp, 2
	str	lr, sp, 0

	fis32_addr1	v4, FIS32_LMANT_LO
	ldr	v0, v4, 0
	setl	v1, 0
	seth	v1, 0
	fis32_addr1	v4, FIS32_RMANT_LO
	ldr	v2, v4, 0
	setl	v3, 0
	seth	v3, 0
	jsr	u32_mul
	fis32_addr1	v4, FIS32_PROD0
	str	v0, v4, 0
	fis32_addr1	v4, FIS32_PROD1
	str	v1, v4, 0
	setl	v4, 0
	seth	v4, 0
	fis32_addr1	v3, FIS32_PROD2
	str	v4, v3, 0

	fis32_addr1	v4, FIS32_LMANT_LO
	ldr	v0, v4, 0
	fis32_addr1	v4, FIS32_RMANT_HI
	ldr	v2, v4, 0
	setl	v1, 0
	seth	v1, 0
	setl	v3, 0
	seth	v3, 0
	jsr	u32_mul
	bsr	fis32_add_cross_to_product

	fis32_addr1	v4, FIS32_RMANT_LO
	ldr	v0, v4, 0
	fis32_addr1	v4, FIS32_LMANT_HI
	ldr	v2, v4, 0
	setl	v1, 0
	seth	v1, 0
	setl	v3, 0
	seth	v3, 0
	jsr	u32_mul
	bsr	fis32_add_cross_to_product

	fis32_addr1	v4, FIS32_LMANT_HI
	ldr	v0, v4, 0
	setl	v1, 0
	seth	v1, 0
	fis32_addr1	v4, FIS32_RMANT_HI
	ldr	v2, v4, 0
	setl	v3, 0
	seth	v3, 0
	jsr	u32_mul
	fis32_addr1	v4, FIS32_PROD2
	ldr	v2, v4, 0
	add	v0, v0, v2
	str	v0, v4, 0

	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

fis32_add_cross_to_product proc
	sub	sp, sp, 2
	str	lr, sp, 0

	mov	v2, v0
	mov	v3, v1
	fis32_addr2	v4, FIS32_PROD1
	ldr	v0, v4, 0
	fis32_addr2	v4, FIS32_PROD2
	ldr	v1, v4, 0
	jsr	u32_add
	fis32_addr2	v4, FIS32_PROD1
	str	v0, v4, 0
	fis32_addr2	v4, FIS32_PROD2
	str	v1, v4, 0

	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

fis32_div_mant proc
	sub	sp, sp, 2
	str	lr, sp, 0

	fis32_addr1	v4, FIS32_LMANT_LO
	ldr	v0, v4, 0
	fis32_addr1	v4, FIS32_LMANT_HI
	ldr	v1, v4, 0
	fis32_addr1	v4, FIS32_RMANT_LO
	ldr	v2, v4, 0
	fis32_addr1	v4, FIS32_RMANT_HI
	ldr	v3, v4, 0

	ltu	v1, v3
	b	fis32_div_init_hi_ge
	b	fis32_div_ratio_lt_one
fis32_div_init_hi_ge:
	ltu	v3, v1
	b	fis32_div_init_hi_eq
	b	fis32_div_ratio_ge_one
fis32_div_init_hi_eq:
	ltu	v0, v2
	b	fis32_div_ratio_ge_one
	b	fis32_div_ratio_lt_one

fis32_div_ratio_ge_one:
	mov	v4, v0
	sub	v0, v0, v2
	sub	v1, v1, v3
	geu	v4, v2
	sub	v1, v1, 1

	sub	sp, sp, FIS32_DIVLOC_FRAME_SIZE
	str	v0, sp, FIS32_DIVLOC_REM_LO
	str	v1, sp, FIS32_DIVLOC_REM_HI
	setl	v0, 1
	seth	v0, 0
	str	v0, sp, FIS32_DIVLOC_QUOT_LO
	setl	v0, 0
	seth	v0, 0
	str	v0, sp, FIS32_DIVLOC_QUOT_HI
	set	v4, 12
	str	v4, sp, FIS32_DIVLOC_COUNT

	set	v4, FIS32_EXP + FIS32_DIVLOC_FRAME_SIZE + 2
	add	v4, sp, v4
	ldr	v0, v4, 0
	add	v0, v0, 1
	str	v0, v4, 0
	b	fis32_div_pair_loop

fis32_div_ratio_lt_one:
	sub	sp, sp, FIS32_DIVLOC_FRAME_SIZE
	str	v0, sp, FIS32_DIVLOC_REM_LO
	str	v1, sp, FIS32_DIVLOC_REM_HI
	setl	v4, 0
	seth	v4, 0
	str	v4, sp, FIS32_DIVLOC_QUOT_LO
	str	v4, sp, FIS32_DIVLOC_QUOT_HI
	set	v4, 12
	str	v4, sp, FIS32_DIVLOC_COUNT
	b	fis32_div_first_bit

fis32_div_first_bit:
	ldr	v0, sp, FIS32_DIVLOC_QUOT_LO
	ldr	v1, sp, FIS32_DIVLOC_QUOT_HI
	mov	v4, v0
	shl	v0, v0, 1
	shl	v1, v1, 1
	ge	v4, 0
	add	v1, v1, 1
	str	v0, sp, FIS32_DIVLOC_QUOT_LO
	str	v1, sp, FIS32_DIVLOC_QUOT_HI

	ldr	v0, sp, FIS32_DIVLOC_REM_LO
	ldr	v1, sp, FIS32_DIVLOC_REM_HI
	mov	v4, v0
	shl	v0, v0, 1
	shl	v1, v1, 1
	ge	v4, 0
	add	v1, v1, 1
	ltu	v1, v3
	b	fis32_div_first_cmp_hi_ge
	b	fis32_div_first_store_rem
fis32_div_first_cmp_hi_ge:
	ltu	v3, v1
	b	fis32_div_first_cmp_hi_eq
	b	fis32_div_first_sub
fis32_div_first_cmp_hi_eq:
	ltu	v0, v2
	b	fis32_div_first_sub
	b	fis32_div_first_store_rem

fis32_div_first_sub:
	mov	v4, v0
	sub	v0, v0, v2
	sub	v1, v1, v3
	geu	v4, v2
	sub	v1, v1, 1
	str	v0, sp, FIS32_DIVLOC_REM_LO
	str	v1, sp, FIS32_DIVLOC_REM_HI
	ldr	v4, sp, FIS32_DIVLOC_QUOT_LO
	add	v4, v4, 1
	str	v4, sp, FIS32_DIVLOC_QUOT_LO
	b	fis32_div_pair_loop

fis32_div_first_store_rem:
	str	v0, sp, FIS32_DIVLOC_REM_LO
	str	v1, sp, FIS32_DIVLOC_REM_HI
	b	fis32_div_pair_loop

fis32_div_pair_loop:
	ldr	v0, sp, FIS32_DIVLOC_QUOT_LO
	ldr	v1, sp, FIS32_DIVLOC_QUOT_HI
	mov	v4, v0
	shr	v4, v4, 14
	shl	v0, v0, 2
	shl	v1, v1, 2
	or	v1, v1, v4
	str	v0, sp, FIS32_DIVLOC_QUOT_LO
	str	v1, sp, FIS32_DIVLOC_QUOT_HI

	ldr	v0, sp, FIS32_DIVLOC_REM_LO
	ldr	v1, sp, FIS32_DIVLOC_REM_HI
	mov	v4, v0
	shr	v4, v4, 14
	shl	v0, v0, 2
	shl	v1, v1, 2
	or	v1, v1, v4

fis32_div_pair_try_sub1:
	ltu	v1, v3
	b	fis32_div_pair_cmp1_hi_ge
	b	fis32_div_pair_store_rem
fis32_div_pair_cmp1_hi_ge:
	ltu	v3, v1
	b	fis32_div_pair_cmp1_hi_eq
	b	fis32_div_pair_sub1
fis32_div_pair_cmp1_hi_eq:
	ltu	v0, v2
	b	fis32_div_pair_sub1
	b	fis32_div_pair_store_rem

fis32_div_pair_sub1:
	mov	v4, v0
	sub	v0, v0, v2
	sub	v1, v1, v3
	geu	v4, v2
	sub	v1, v1, 1
	ldr	v4, sp, FIS32_DIVLOC_QUOT_LO
	add	v4, v4, 1
	str	v4, sp, FIS32_DIVLOC_QUOT_LO

fis32_div_pair_try_sub2:
	ltu	v1, v3
	b	fis32_div_pair_cmp2_hi_ge
	b	fis32_div_pair_store_rem
fis32_div_pair_cmp2_hi_ge:
	ltu	v3, v1
	b	fis32_div_pair_cmp2_hi_eq
	b	fis32_div_pair_sub2
fis32_div_pair_cmp2_hi_eq:
	ltu	v0, v2
	b	fis32_div_pair_sub2
	b	fis32_div_pair_store_rem

fis32_div_pair_sub2:
	mov	v4, v0
	sub	v0, v0, v2
	sub	v1, v1, v3
	geu	v4, v2
	sub	v1, v1, 1
	ldr	v4, sp, FIS32_DIVLOC_QUOT_LO
	add	v4, v4, 1
	str	v4, sp, FIS32_DIVLOC_QUOT_LO

fis32_div_pair_try_sub3:
	ltu	v1, v3
	b	fis32_div_pair_cmp3_hi_ge
	b	fis32_div_pair_store_rem
fis32_div_pair_cmp3_hi_ge:
	ltu	v3, v1
	b	fis32_div_pair_cmp3_hi_eq
	b	fis32_div_pair_sub3
fis32_div_pair_cmp3_hi_eq:
	ltu	v0, v2
	b	fis32_div_pair_sub3
	b	fis32_div_pair_store_rem

fis32_div_pair_sub3:
	mov	v4, v0
	sub	v0, v0, v2
	sub	v1, v1, v3
	geu	v4, v2
	sub	v1, v1, 1
	ldr	v4, sp, FIS32_DIVLOC_QUOT_LO
	add	v4, v4, 1
	str	v4, sp, FIS32_DIVLOC_QUOT_LO

fis32_div_pair_store_rem:
	str	v0, sp, FIS32_DIVLOC_REM_LO
	str	v1, sp, FIS32_DIVLOC_REM_HI

fis32_div_next:
	ldr	v4, sp, FIS32_DIVLOC_COUNT
	sub	v4, v4, 1
	str	v4, sp, FIS32_DIVLOC_COUNT
	bne	fis32_div_pair_loop, v4, 0

fis32_div_done:
	ldr	v0, sp, FIS32_DIVLOC_QUOT_LO
	ldr	v1, sp, FIS32_DIVLOC_QUOT_HI
	add	sp, sp, FIS32_DIVLOC_FRAME_SIZE
	add	v0, v0, 1
	ne	v0, 0
	b	fis32_div_round_carry
	b	fis32_div_round_check
fis32_div_round_carry:
	add	v1, v1, 1
fis32_div_round_check:
	jsr	u32_shr1
	set	v4, $0100
	ltu	v1, v4
	b	fis32_div_round_overflow
	b	fis32_div_store
fis32_div_round_overflow:
	setl	v0, 0
	seth	v0, 0
	set	v1, $0080
	fis32_addr1	v4, FIS32_EXP
	ldr	v2, v4, 0
	add	v2, v2, 1
	str	v2, v4, 0
fis32_div_store:
fis32_div_return:
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

include int32.inc

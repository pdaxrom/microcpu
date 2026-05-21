;
; FIS16 floating point support for microcpu.
;
; This include emits procedure code and includes int32.inc internally. Include
; it after the code that calls these routines, or branch around it.
;
; Format (FIS16):
;   v1:v0 is one floating point number.
;   v1 bit 15      - sign
;   v1 bits 14..8  - reserved, keep zero
;   v1 bits 7..0   - exponent, biased by 128
;   v0             - explicit normalized mantissa, 0x8000..0xffff
;
; Value:
;   zero is v1 = 0, v0 = 0
;   nonzero = (-1)^sign * (mantissa / 32768) * 2^(exponent - 128)
;
; ABI:
;   lhs/result: v1:v0
;   rhs:        v3:v2
;   v4 is scratch.
;
; Routines:
;   fadd, fsub, fmul, fdiv
;
; Overflow saturates to exponent 255, mantissa 0xffff. Underflow becomes zero.
; Division by zero returns saturated max with quotient sign. Routines use a
; per-call stack frame and are reentrant.
;

FIS_BIAS equ 128
FIS_LSIGN equ 2
FIS_RSIGN equ 4
FIS_SIGN equ 6
FIS_LEXP equ 8
FIS_REXP equ 10
FIS_EXP equ 12
FIS_LMANT equ 14
FIS_RMANT equ 16
FIS_LRAW equ 18
FIS_RRAW equ 20
FIS_FRAME_SIZE equ 22

	macro	fis_addr
	set	#1, #2
	add	#1, sp, #1
	endm

fadd proc
	set	v4, FIS_FRAME_SIZE
	sub	sp, sp, v4
	str	lr, sp, 0

	eq	v0, 0
	b	fadd_lhs_nonzero
	mov	v0, v2
	mov	v1, v3
	b	fadd_return

fadd_lhs_nonzero:
	eq	v2, 0
	b	fadd_rhs_nonzero
	b	fadd_return

fadd_rhs_nonzero:
	fis_addr	v4, FIS_LRAW
	str	v1, v4, 0
	fis_addr	v4, FIS_RRAW
	str	v3, v4, 0

	setl	v4, 0
	seth	v4, 0
	ge	v1, 0
	setl	v4, 1
	fis_addr	v3, FIS_LSIGN
	str	v4, v3, 0

	fis_addr	v4, FIS_RRAW
	ldr	v3, v4, 0
	setl	v4, 0
	seth	v4, 0
	ge	v3, 0
	setl	v4, 1
	fis_addr	v3, FIS_RSIGN
	str	v4, v3, 0

	fis_addr	v4, FIS_LRAW
	ldr	v1, v4, 0
	fis_addr	v4, FIS_RRAW
	ldr	v3, v4, 0
	set	v4, $00ff
	and	v1, v1, v4
	and	v3, v3, v4
	fis_addr	v4, FIS_LEXP
	str	v1, v4, 0
	fis_addr	v4, FIS_REXP
	str	v3, v4, 0
	fis_addr	v4, FIS_LMANT
	str	v0, v4, 0
	fis_addr	v4, FIS_RMANT
	str	v2, v4, 0

	ltu	v1, v3
	b	fadd_lhs_exp_ge

	sub	v2, v3, v1
	fis_addr	v4, FIS_EXP
	str	v3, v4, 0
	fis_addr	v4, FIS_LMANT
	ldr	v0, v4, 0
	b	fadd_shift_lmant

fadd_lhs_exp_ge:
	sub	v2, v1, v3
	fis_addr	v4, FIS_EXP
	str	v1, v4, 0
	fis_addr	v4, FIS_RMANT
	ldr	v0, v4, 0
	b	fadd_shift_rmant

fadd_shift_lmant:
	set	v3, 16
	ltu	v2, v3
	b	fadd_lmant_zero
fadd_shift_lmant_loop:
	eq	v2, 0
	b	fadd_shift_lmant_body
	b	fadd_store_lmant
fadd_shift_lmant_body:
	shr	v0, v0, 1
	sub	v2, v2, 1
	b	fadd_shift_lmant_loop
fadd_lmant_zero:
	setl	v0, 0
	seth	v0, 0
fadd_store_lmant:
	fis_addr	v4, FIS_LMANT
	str	v0, v4, 0
	b	fadd_after_align

fadd_shift_rmant:
	set	v3, 16
	ltu	v2, v3
	b	fadd_rmant_zero
fadd_shift_rmant_loop:
	eq	v2, 0
	b	fadd_shift_rmant_body
	b	fadd_store_rmant
fadd_shift_rmant_body:
	shr	v0, v0, 1
	sub	v2, v2, 1
	b	fadd_shift_rmant_loop
fadd_rmant_zero:
	setl	v0, 0
	seth	v0, 0
fadd_store_rmant:
	fis_addr	v4, FIS_RMANT
	str	v0, v4, 0

fadd_after_align:
	fis_addr	v4, FIS_LSIGN
	ldr	v0, v4, 0
	fis_addr	v4, FIS_RSIGN
	ldr	v1, v4, 0
	eq	v0, v1
	b	fadd_signs_differ

	fis_addr	v4, FIS_LMANT
	ldr	v0, v4, 0
	mov	v4, v0
	fis_addr	v3, FIS_RMANT
	ldr	v2, v3, 0
	add	v0, v0, v2
	ltu	v0, v4
	b	fadd_same_no_carry

	shr	v0, v0, 1
	setl	v4, 0
	seth	v4, $80
	or	v0, v0, v4
	fis_addr	v4, FIS_EXP
	ldr	v1, v4, 0
	add	v1, v1, 1
	str	v1, v4, 0

fadd_same_no_carry:
	fis_addr	v4, FIS_LSIGN
	ldr	v4, v4, 0
	b	fadd_pack

fadd_signs_differ:
	fis_addr	v4, FIS_LMANT
	ldr	v0, v4, 0
	fis_addr	v4, FIS_RMANT
	ldr	v1, v4, 0
	eq	v0, v1
	b	fadd_diff_nonzero
	setl	v0, 0
	seth	v0, 0
	setl	v1, 0
	seth	v1, 0
	b	fadd_return

fadd_diff_nonzero:
	ltu	v0, v1
	b	fadd_lmant_ge_rmant

	sub	v0, v1, v0
	fis_addr	v4, FIS_RSIGN
	ldr	v4, v4, 0
	b	fadd_normalize

fadd_lmant_ge_rmant:
	sub	v0, v0, v1
	fis_addr	v4, FIS_LSIGN
	ldr	v4, v4, 0

fadd_normalize:
	fis_addr	v1, FIS_EXP
	ldr	v1, v1, 0
fadd_norm_loop:
	eq	v0, 0
	b	fadd_norm_not_zero
	setl	v1, 0
	seth	v1, 0
	b	fadd_return
fadd_norm_not_zero:
	eq	v1, 0
	b	fadd_norm_exp_nonzero
	setl	v0, 0
	seth	v0, 0
	b	fadd_return
fadd_norm_exp_nonzero:
	ge	v0, 0
	b	fadd_norm_pack
	shl	v0, v0, 1
	sub	v1, v1, 1
	b	fadd_norm_loop

fadd_norm_pack:
	fis_addr	v3, FIS_EXP
	str	v1, v3, 0
	b	fadd_pack

fadd_pack:
	fis_addr	v3, FIS_EXP
	ldr	v1, v3, 0
	bsr	fis_pack

fadd_return:
	ldr	lr, sp, 0
	set	v4, FIS_FRAME_SIZE
	add	sp, sp, v4
	rts
	endp

fsub proc
	setl	v4, 0
	seth	v4, $80
	xor	v3, v3, v4
	b	fadd
	endp

fmul proc
	set	v4, FIS_FRAME_SIZE
	sub	sp, sp, v4
	str	lr, sp, 0

	eq	v0, 0
	b	fmul_lhs_nonzero
	b	fmul_zero
fmul_lhs_nonzero:
	eq	v2, 0
	b	fmul_rhs_nonzero
	b	fmul_zero

fmul_rhs_nonzero:
	bsr	fis_store_muldiv_parts
	fis_addr	v4, FIS_LEXP
	ldr	v0, v4, 0
	fis_addr	v4, FIS_REXP
	ldr	v1, v4, 0
	add	v1, v1, v0
	set	v0, FIS_BIAS
	sub	v1, v1, v0
	fis_addr	v4, FIS_EXP
	str	v1, v4, 0

	fis_addr	v4, FIS_LMANT
	ldr	v0, v4, 0
	setl	v1, 0
	seth	v1, 0
	fis_addr	v4, FIS_RMANT
	ldr	v2, v4, 0
	setl	v3, 0
	seth	v3, 0
	jsr	u32_mul

	ge	v1, 0
	b	fmul_product_ge_2

	set	v2, 15
	jsr	u32_shr
	b	fmul_pack

fmul_product_ge_2:
	mov	v0, v1
	fis_addr	v4, FIS_EXP
	ldr	v1, v4, 0
	add	v1, v1, 1
	str	v1, v4, 0
	b	fmul_pack

fmul_pack:
	fis_addr	v4, FIS_SIGN
	ldr	v4, v4, 0
	fis_addr	v3, FIS_EXP
	ldr	v1, v3, 0
	bsr	fis_pack
	b	fmul_done

fmul_zero:
	setl	v0, 0
	seth	v0, 0
	setl	v1, 0
	seth	v1, 0

fmul_done:
	ldr	lr, sp, 0
	set	v4, FIS_FRAME_SIZE
	add	sp, sp, v4
	rts
	endp

fdiv proc
	set	v4, FIS_FRAME_SIZE
	sub	sp, sp, v4
	str	lr, sp, 0

	eq	v0, 0
	b	fdiv_lhs_nonzero
	b	fdiv_zero
fdiv_lhs_nonzero:
	bsr	fis_store_muldiv_parts
	eq	v2, 0
	b	fdiv_rhs_nonzero
	fis_addr	v4, FIS_SIGN
	ldr	v4, v4, 0
	bsr	fis_overflow_value
	b	fdiv_done

fdiv_rhs_nonzero:
	fis_addr	v4, FIS_LEXP
	ldr	v1, v4, 0
	set	v0, FIS_BIAS
	add	v1, v1, v0
	fis_addr	v4, FIS_REXP
	ldr	v0, v4, 0
	sub	v1, v1, v0
	fis_addr	v4, FIS_EXP
	str	v1, v4, 0

	fis_addr	v4, FIS_LMANT
	ldr	v4, v4, 0
	mov	v0, v4
	and	v0, v0, 1
	shl	v0, v0, 15
	mov	v1, v4
	shr	v1, v1, 1
	fis_addr	v4, FIS_RMANT
	ldr	v2, v4, 0
	setl	v3, 0
	seth	v3, 0
	jsr	u32_div

	ge	v0, 0
	b	fdiv_pack

fdiv_quot_norm:
	shl	v0, v0, 1
	fis_addr	v4, FIS_EXP
	ldr	v1, v4, 0
	sub	v1, v1, 1
	str	v1, v4, 0

fdiv_pack:
	fis_addr	v4, FIS_SIGN
	ldr	v4, v4, 0
	fis_addr	v3, FIS_EXP
	ldr	v1, v3, 0
	bsr	fis_pack
	b	fdiv_done

fdiv_zero:
	setl	v0, 0
	seth	v0, 0
	setl	v1, 0
	seth	v1, 0

fdiv_done:
	ldr	lr, sp, 0
	set	v4, FIS_FRAME_SIZE
	add	sp, sp, v4
	rts
	endp

fis_store_muldiv_parts proc
	fis_addr	v4, FIS_LRAW
	str	v1, v4, 0
	fis_addr	v4, FIS_RRAW
	str	v3, v4, 0

	setl	v4, 0
	seth	v4, 0
	ge	v1, 0
	setl	v4, 1
	fis_addr	v3, FIS_LSIGN
	str	v4, v3, 0

	fis_addr	v4, FIS_RRAW
	ldr	v3, v4, 0
	setl	v4, 0
	seth	v4, 0
	ge	v3, 0
	setl	v4, 1
	fis_addr	v3, FIS_RSIGN
	str	v4, v3, 0

	fis_addr	v4, FIS_LSIGN
	ldr	v4, v4, 0
	fis_addr	v3, FIS_RSIGN
	ldr	v3, v3, 0
	xor	v4, v4, v3
	fis_addr	v3, FIS_SIGN
	str	v4, v3, 0

	fis_addr	v4, FIS_LRAW
	ldr	v1, v4, 0
	fis_addr	v4, FIS_RRAW
	ldr	v3, v4, 0
	set	v4, $00ff
	and	v1, v1, v4
	and	v3, v3, v4
	fis_addr	v4, FIS_LEXP
	str	v1, v4, 0
	fis_addr	v4, FIS_REXP
	str	v3, v4, 0
	fis_addr	v4, FIS_LMANT
	str	v0, v4, 0
	fis_addr	v4, FIS_RMANT
	str	v2, v4, 0
	rts
	endp

fis_pack proc
	eq	v0, 0
	b	fis_pack_nonzero
	setl	v1, 0
	seth	v1, 0
	rts

fis_pack_nonzero:
	ge	v1, 0
	b	fis_pack_zero
	eq	v1, 0
	b	fis_pack_exp_nonzero
fis_pack_zero:
	setl	v0, 0
	seth	v0, 0
	setl	v1, 0
	seth	v1, 0
	rts

fis_pack_exp_nonzero:
	set	v2, $ff00
	and	v3, v1, v2
	eq	v3, 0
	b	fis_pack_overflow
	set	v2, $00ff
	and	v1, v1, v2
	eq	v4, 0
	b	fis_pack_sign
	rts

fis_pack_sign:
	setl	v2, 0
	seth	v2, $80
	or	v1, v1, v2
	rts

fis_pack_overflow:
	b	fis_overflow_value
	endp

fis_overflow_value proc
	setl	v0, $ff
	seth	v0, $ff
	setl	v1, $ff
	seth	v1, 0
	eq	v4, 0
	b	fis_overflow_sign
	rts
fis_overflow_sign:
	setl	v2, 0
	seth	v2, $80
	or	v1, v1, v2
	rts
	endp

include int32.inc

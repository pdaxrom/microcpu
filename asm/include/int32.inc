;
; 32-bit integer support routines for microcpu.
;
; This include emits procedure code. Include it after the code that calls these
; routines, or branch around it.
;
; ABI:
;   - 32-bit values are held as hi:lo word pairs.
;   - lhs/result: v1:v0
;   - rhs:        v3:v2
;   - division returns quotient in v1:v0 and remainder in v3:v2.
;   - division by zero returns quotient $ffffffff and remainder = dividend.
;   - i32_mul returns the low 32 product bits; for two's complement this is the
;     same bit pattern as u32_mul.
;   - count shifts use v2 as count and consume it.
;   - v4 is scratch unless noted otherwise.
;
; The routine set follows the usual small 8/16-bit CPU software arithmetic
; pattern: carry/borrow is synthesized with unsigned compares, multiply is
; shift-and-add, and divide is restoring long division.
;

u32_add proc
	mov	v4, v0
	add	v0, v0, v2
	add	v1, v1, v3
	geu	v0, v4
	add	v1, v1, 1
	rts
	endp

i32_add proc
	b	u32_add
	endp

u32_sub proc
	mov	v4, v0
	sub	v0, v0, v2
	sub	v1, v1, v3
	geu	v4, v2
	sub	v1, v1, 1
	rts
	endp

i32_sub proc
	b	u32_sub
	endp

u32_neg proc
	inv	v0, v0
	inv	v1, v1
	add	v0, v0, 1
	ne	v0, 0
	add	v1, v1, 1
	rts
	endp

i32_neg proc
	b	u32_neg
	endp

u32_shl1 proc
	mov	v4, v0
	shl	v0, v0, 1
	shl	v1, v1, 1
	ge	v4, 0
	add	v1, v1, 1
	rts
	endp

u32_shr1 proc
	mov	v4, v1
	shr	v1, v1, 1
	shr	v0, v0, 1
	bts	v4, 1
	b	u32_shr1_done
	setl	v4, 0
	seth	v4, $80
	or	v0, v0, v4
u32_shr1_done:
	rts
	endp

i32_sar1 proc
	mov	v4, v1
	shr	v1, v1, 1
	shr	v0, v0, 1
	ge	v4, 0
	b	i32_sar1_neg

	bts	v4, 1
	b	i32_sar1_done
	setl	v4, 0
	seth	v4, $80
	or	v0, v0, v4
	b	i32_sar1_done

i32_sar1_neg:
	bts	v4, 1
	b	i32_sar1_neg_no_low
	setl	v4, 0
	seth	v4, $80
	or	v0, v0, v4
	or	v1, v1, v4
	b	i32_sar1_done

i32_sar1_neg_no_low:
	setl	v4, 0
	seth	v4, $80
	or	v1, v1, v4

i32_sar1_done:
	rts
	endp

;
; Shift left through explicit carry.
;   in:  v1:v0 value, v4 bit 0 carry-in
;   out: v1:v0 shifted value, v4 bit 0 carry-out
;   clobbers: v2, v3
;
u32_shl1c proc
	and	v4, v4, 1
	mov	v2, v1
	mov	v3, v0
	shl	v0, v0, 1
	or	v0, v0, v4
	shl	v1, v1, 1
	ge	v3, 0
	add	v1, v1, 1
	setl	v4, 0
	seth	v4, 0
	ge	v2, 0
	setl	v4, 1
	rts
	endp

;
; Shift right through explicit carry.
;   in:  v1:v0 value, v4 bit 0 carry-in
;   out: v1:v0 shifted value, v4 bit 0 carry-out
;   clobbers: v2, v3
;
u32_shr1c proc
	and	v4, v4, 1
	mov	v2, v0
	mov	v3, v1
	shr	v1, v1, 1
	shr	v0, v0, 1
	bts	v3, 1
	b	u32_shr1c_no_mid
	setl	v3, 0
	seth	v3, $80
	or	v0, v0, v3
u32_shr1c_no_mid:
	eq	v4, 0
	b	u32_shr1c_carry_in
	b	u32_shr1c_set_out
u32_shr1c_carry_in:
	setl	v3, 0
	seth	v3, $80
	or	v1, v1, v3
u32_shr1c_set_out:
	setl	v4, 0
	seth	v4, 0
	bts	v2, 1
	b	u32_shr1c_done
	setl	v4, 1
u32_shr1c_done:
	rts
	endp

u32_shl proc
u32_shl_loop:
	eq	v2, 0
	b	u32_shl_body
	rts
u32_shl_body:
	mov	v4, v0
	shl	v0, v0, 1
	shl	v1, v1, 1
	ge	v4, 0
	add	v1, v1, 1
	sub	v2, v2, 1
	b	u32_shl_loop
	endp

u32_shr proc
u32_shr_loop:
	eq	v2, 0
	b	u32_shr_body
	rts
u32_shr_body:
	mov	v4, v1
	shr	v1, v1, 1
	shr	v0, v0, 1
	bts	v4, 1
	b	u32_shr_no_mid
	setl	v4, 0
	seth	v4, $80
	or	v0, v0, v4
u32_shr_no_mid:
	sub	v2, v2, 1
	b	u32_shr_loop
	endp

i32_sar proc
i32_sar_loop:
	eq	v2, 0
	b	i32_sar_body
	rts
i32_sar_body:
	mov	v4, v1
	shr	v1, v1, 1
	shr	v0, v0, 1
	ge	v4, 0
	b	i32_sar_neg

	bts	v4, 1
	b	i32_sar_next
	setl	v4, 0
	seth	v4, $80
	or	v0, v0, v4
	b	i32_sar_next

i32_sar_neg:
	bts	v4, 1
	b	i32_sar_neg_no_low
	setl	v4, 0
	seth	v4, $80
	or	v0, v0, v4
	or	v1, v1, v4
	b	i32_sar_next

i32_sar_neg_no_low:
	setl	v4, 0
	seth	v4, $80
	or	v1, v1, v4

i32_sar_next:
	sub	v2, v2, 1
	b	i32_sar_loop
	endp

u32_mul proc
	sub	sp, sp, 4
	str	v0, sp, 0
	str	v1, sp, 2
	setl	v0, 0
	seth	v0, 0
	setl	v1, 0
	seth	v1, 0

u32_mul_loop:
	ne	v2, 0
	b	u32_mul_check_hi
	b	u32_mul_body
u32_mul_check_hi:
	ne	v3, 0
	b	u32_mul_done
	b	u32_mul_body

u32_mul_body:
	bts	v2, 1
	b	u32_mul_no_add
	ldr	v4, sp, 0
	add	v0, v0, v4
	ltu	v0, v4
	b	u32_mul_add_no_carry
	ldr	v4, sp, 2
	add	v1, v1, v4
	add	v1, v1, 1
	b	u32_mul_no_add
u32_mul_add_no_carry:
	ldr	v4, sp, 2
	add	v1, v1, v4

u32_mul_no_add:
	ldr	v4, sp, 0
	ge	v4, 0
	b	u32_mul_shift_m_carry
	shl	v4, v4, 1
	str	v4, sp, 0
	ldr	v4, sp, 2
	shl	v4, v4, 1
	str	v4, sp, 2
	b	u32_mul_shift_q

u32_mul_shift_m_carry:
	shl	v4, v4, 1
	str	v4, sp, 0
	ldr	v4, sp, 2
	shl	v4, v4, 1
	add	v4, v4, 1
	str	v4, sp, 2

u32_mul_shift_q:
	mov	v4, v3
	shr	v3, v3, 1
	shr	v2, v2, 1
	bts	v4, 1
	b	u32_mul_loop
	setl	v4, 0
	seth	v4, $80
	or	v2, v2, v4
	b	u32_mul_loop

u32_mul_done:
	add	sp, sp, 4
	rts
	endp

i32_mul proc
	b	u32_mul
	endp

u32_div proc
	ne	v2, 0
	b	u32_div_check_hi
	b	u32_div_nonzero
u32_div_check_hi:
	ne	v3, 0
	b	u32_div_zero
	b	u32_div_nonzero

u32_div_zero:
	mov	v2, v0
	mov	v3, v1
	setl	v0, $ff
	seth	v0, $ff
	setl	v1, $ff
	seth	v1, $ff
	rts

u32_div_nonzero:
	sub	sp, sp, 12
	str	v2, sp, 4
	str	v3, sp, 6
	setl	v4, 0
	seth	v4, 0
	str	v4, sp, 0
	str	v4, sp, 2
	setl	v4, 32
	seth	v4, 0
	str	v4, sp, 8

u32_div_loop:
	setl	v4, 0
	seth	v4, 0
	ge	v1, 0
	setl	v4, 1
	str	v4, sp, 10

	mov	v4, v0
	shl	v0, v0, 1
	shl	v1, v1, 1
	ge	v4, 0
	add	v1, v1, 1

	ldr	v2, sp, 0
	ldr	v3, sp, 2
	mov	v4, v2
	shl	v2, v2, 1
	shl	v3, v3, 1
	ge	v4, 0
	add	v3, v3, 1
	ldr	v4, sp, 10
	or	v2, v2, v4
	str	v2, sp, 0
	str	v3, sp, 2

	ldr	v4, sp, 6
	ltu	v3, v4
	b	u32_div_hi_ge
	b	u32_div_next
u32_div_hi_ge:
	ltu	v4, v3
	b	u32_div_hi_eq
	b	u32_div_do_sub
u32_div_hi_eq:
	ldr	v4, sp, 4
	ltu	v2, v4
	b	u32_div_do_sub
	b	u32_div_next

u32_div_do_sub:
	ldr	v4, sp, 4
	ltu	v2, v4
	b	u32_div_sub_no_borrow
	sub	v2, v2, v4
	ldr	v4, sp, 6
	sub	v3, v3, v4
	sub	v3, v3, 1
	b	u32_div_sub_done
u32_div_sub_no_borrow:
	sub	v2, v2, v4
	ldr	v4, sp, 6
	sub	v3, v3, v4
u32_div_sub_done:
	str	v2, sp, 0
	str	v3, sp, 2
	add	v0, v0, 1

u32_div_next:
	ldr	v4, sp, 8
	sub	v4, v4, 1
	str	v4, sp, 8
	eq	v4, 0
	b	u32_div_loop

	ldr	v2, sp, 0
	ldr	v3, sp, 2
	add	sp, sp, 12
	rts
	endp

i32_div proc
	ne	v2, 0
	b	i32_div_check_hi
	b	i32_div_nonzero
i32_div_check_hi:
	ne	v3, 0
	b	i32_div_zero
	b	i32_div_nonzero

i32_div_zero:
	mov	v2, v0
	mov	v3, v1
	setl	v0, $ff
	seth	v0, $ff
	setl	v1, $ff
	seth	v1, $ff
	rts

i32_div_nonzero:
	sub	sp, sp, 6
	str	lr, sp, 0
	setl	v4, 0
	seth	v4, 0
	str	v4, sp, 2	; quotient sign
	str	v4, sp, 4	; remainder sign

	ge	v1, 0
	b	i32_div_abs_dividend
	b	i32_div_check_divisor
i32_div_abs_dividend:
	setl	v4, 1
	seth	v4, 0
	str	v4, sp, 2
	str	v4, sp, 4
	inv	v0, v0
	inv	v1, v1
	add	v0, v0, 1
	ne	v0, 0
	add	v1, v1, 1

i32_div_check_divisor:
	ge	v3, 0
	b	i32_div_abs_divisor
	b	i32_div_call_unsigned
i32_div_abs_divisor:
	ldr	v4, sp, 2
	xor	v4, v4, 1
	str	v4, sp, 2
	inv	v2, v2
	inv	v3, v3
	add	v2, v2, 1
	ne	v2, 0
	add	v3, v3, 1

i32_div_call_unsigned:
	add	lr, pc, 3
	b	u32_div

	ldr	v4, sp, 2
	eq	v4, 0
	b	i32_div_neg_quot
	b	i32_div_rem_sign
i32_div_neg_quot:
	inv	v0, v0
	inv	v1, v1
	add	v0, v0, 1
	ne	v0, 0
	add	v1, v1, 1

i32_div_rem_sign:
	ldr	v4, sp, 4
	eq	v4, 0
	b	i32_div_neg_rem
	b	i32_div_done
i32_div_neg_rem:
	inv	v2, v2
	inv	v3, v3
	add	v2, v2, 1
	ne	v2, 0
	add	v3, v3, 1

i32_div_done:
	ldr	lr, sp, 0
	add	sp, sp, 6
	rts
	endp

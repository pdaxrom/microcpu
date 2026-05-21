;
; 16-bit runtime helpers for the Small-C microcpu backend.
; Inputs follow the backend convention: v0 is primary, v1 is secondary.
;

__sc_true:
	set	v0, 1
	rts

__sc_false:
	clr	v0
	rts

__eq:
	ne	v1, v0
	b	__sc_true
	b	__sc_false

__ne:
	eq	v1, v0
	b	__sc_true
	b	__sc_false

__lt:
	ge	v1, v0
	b	__sc_true
	b	__sc_false

__ge:
	lt	v1, v0
	b	__sc_true
	b	__sc_false

__gt:
	ge	v0, v1
	b	__sc_true
	b	__sc_false

__le:
	lt	v0, v1
	b	__sc_true
	b	__sc_false

__ult:
	geu	v1, v0
	b	__sc_true
	b	__sc_false

__uge:
	ltu	v1, v0
	b	__sc_true
	b	__sc_false

__ugt:
	geu	v0, v1
	b	__sc_true
	b	__sc_false

__ule:
	ltu	v0, v1
	b	__sc_true
	b	__sc_false

__lneg:
	ne	v0, 0
	b	__sc_true
	b	__sc_false

__neg16:
	inv	v0, v0
	add	v0, v0, 1
	rts

__mul16:
	mov	v2, v0
	clr	v0
__mul16_loop:
	eq	v2, 0
	b	__mul16_body
	rts
__mul16_body:
	bts	v2, 1
	b	__mul16_no_add
	add	v0, v0, v1
__mul16_no_add:
	shl	v1, v1, 1
	shr	v2, v2, 1
	b	__mul16_loop

__udiv16:
	ne	v1, 0
	b	__udiv16_zero
	clr	v2
__udiv16_loop:
	ltu	v0, v1
	b	__udiv16_sub
	mov	v0, v2
	rts
__udiv16_sub:
	sub	v0, v0, v1
	add	v2, v2, 1
	b	__udiv16_loop
__udiv16_zero:
	set	v0, $ffff
	rts

__umod16:
	ne	v1, 0
	b	__umod16_zero
__umod16_loop:
	ltu	v0, v1
	b	__umod16_sub
	rts
__umod16_sub:
	sub	v0, v0, v1
	b	__umod16_loop
__umod16_zero:
	set	v0, $ffff
	rts

__sdiv16:
	cc_push	lr
	clr	v2
	ge	v0, 0
	b	__sdiv16_neg_lhs
	b	__sdiv16_check_rhs
__sdiv16_neg_lhs:
	inv	v0, v0
	add	v0, v0, 1
	xor	v2, v2, 1
__sdiv16_check_rhs:
	ge	v1, 0
	b	__sdiv16_neg_rhs
	b	__sdiv16_call
__sdiv16_neg_rhs:
	inv	v1, v1
	add	v1, v1, 1
	xor	v2, v2, 1
__sdiv16_call:
	cc_push	v2
	jsr	__udiv16
	cc_pop	v2
	eq	v2, 0
	b	__sdiv16_neg_result
	b	__sdiv16_done
__sdiv16_neg_result:
	inv	v0, v0
	add	v0, v0, 1
__sdiv16_done:
	cc_pop	lr
	rts

__smod16:
	cc_push	lr
	clr	v2
	ge	v0, 0
	b	__smod16_neg_lhs
	b	__smod16_check_rhs
__smod16_neg_lhs:
	inv	v0, v0
	add	v0, v0, 1
	set	v2, 1
__smod16_check_rhs:
	ge	v1, 0
	b	__smod16_neg_rhs
	b	__smod16_call
__smod16_neg_rhs:
	inv	v1, v1
	add	v1, v1, 1
__smod16_call:
	cc_push	v2
	jsr	__umod16
	cc_pop	v2
	eq	v2, 0
	b	__smod16_neg_result
	b	__smod16_done
__smod16_neg_result:
	inv	v0, v0
	add	v0, v0, 1
__smod16_done:
	cc_pop	lr
	rts

__shl16:
	mov	v2, v0
	mov	v0, v1
__shl16_loop:
	eq	v2, 0
	b	__shl16_body
	rts
__shl16_body:
	shl	v0, v0, 1
	sub	v2, v2, 1
	b	__shl16_loop

__sar16:
	mov	v2, v0
	mov	v0, v1
__sar16_loop:
	eq	v2, 0
	b	__sar16_body
	rts
__sar16_body:
	ge	v0, 0
	b	__sar16_negative
	shr	v0, v0, 1
	b	__sar16_next
__sar16_negative:
	shr	v0, v0, 1
	set	v3, $8000
	or	v0, v0, v3
__sar16_next:
	sub	v2, v2, 1
	b	__sar16_loop

__switch:
	rts

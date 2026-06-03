;
; Experimental p-code interpreter for Small-C microcpu tests.
; Stage 1 implements the pure p-code subset used by pcode-tests/001..006.
;

include ../../asm/include/pseudo.inc

extern __pcode_entry

public __pcd_vstk
public __pcd_vstkend
public __pcd_frames
public __pcd_frame0
public __pcd_frameend
public __pcd_nstk
public __pcd_nstktop

PCODE_FRAME_SIZE	equ	64
PCODE_CALL_DEPTH	equ	16
PCODE_STACK_BYTES	equ	512

	macro	pcode_dispatch
	set	v1, #1
	eq	v0, v1
	b	*+6
	jmp	#2
	endm

__pcode_startup:
	set	sp, __pcode_native_stktop
	sub	sp, sp, 2
	set	v3, __pcode_stack
	set	v4, __pcode_frame0
	set	v1, __pcode_depth
	clr	v0
	str	v0, v1, 0
	set	v2, __pcode_entry
	ldr	v2, v2, 0
	b	__pcode_loop

__pcode_loop:
	ldrl	v0, v2, 0
	seth	v0, 0
	add	v2, v2, 1
	pcode_dispatch	$02, __pcode_op_iconst_m1
	pcode_dispatch	$03, __pcode_op_iconst_0
	pcode_dispatch	$04, __pcode_op_iconst_1
	pcode_dispatch	$05, __pcode_op_iconst_2
	pcode_dispatch	$06, __pcode_op_iconst_s8
	pcode_dispatch	$07, __pcode_op_iconst_u16
	pcode_dispatch	$08, __pcode_op_drop
	pcode_dispatch	$09, __pcode_op_dup
	pcode_dispatch	$0a, __pcode_op_swap
	pcode_dispatch	$0b, __pcode_op_addi_s8
	pcode_dispatch	$0c, __pcode_op_subi_s8
	pcode_dispatch	$0d, __pcode_op_eqi_s8
	pcode_dispatch	$0e, __pcode_op_addi_u16
	pcode_dispatch	$10, __pcode_op_llocal_0
	pcode_dispatch	$11, __pcode_op_llocal_1
	pcode_dispatch	$12, __pcode_op_llocal_2
	pcode_dispatch	$13, __pcode_op_llocal_3
	pcode_dispatch	$14, __pcode_op_slocal_0
	pcode_dispatch	$15, __pcode_op_slocal_1
	pcode_dispatch	$16, __pcode_op_slocal_2
	pcode_dispatch	$17, __pcode_op_slocal_3
	pcode_dispatch	$18, __pcode_op_llocal_s8
	pcode_dispatch	$19, __pcode_op_slocal_s8
	pcode_dispatch	$1a, __pcode_op_llocal_u16
	pcode_dispatch	$1b, __pcode_op_slocal_u16
	pcode_dispatch	$1c, __pcode_op_addr_local_s8
	pcode_dispatch	$1d, __pcode_op_addr_local_u16
	pcode_dispatch	$20, __pcode_op_lglobal_u16
	pcode_dispatch	$21, __pcode_op_sglobal_u16
	pcode_dispatch	$22, __pcode_op_addr_global_u16
	pcode_dispatch	$30, __pcode_op_lbyte
	pcode_dispatch	$31, __pcode_op_sbyte
	pcode_dispatch	$32, __pcode_op_lword
	pcode_dispatch	$33, __pcode_op_sword
	pcode_dispatch	$40, __pcode_op_jmp_s8
	pcode_dispatch	$41, __pcode_op_jmp_s16
	pcode_dispatch	$42, __pcode_op_jz_s8
	pcode_dispatch	$43, __pcode_op_jz_s16
	pcode_dispatch	$44, __pcode_op_jnz_s8
	pcode_dispatch	$45, __pcode_op_jnz_s16
	pcode_dispatch	$50, __pcode_op_call_u16
	pcode_dispatch	$51, __pcode_op_ret
	pcode_dispatch	$54, __pcode_op_ncall_u8
	pcode_dispatch	$55, __pcode_op_ncall_addr_u16
	pcode_dispatch	$57, __pcode_op_icall_u8
	pcode_dispatch	$58, __pcode_op_call0_u16
	pcode_dispatch	$59, __pcode_op_call1_u16
	pcode_dispatch	$5a, __pcode_op_call2_u16
	pcode_dispatch	$5b, __pcode_op_ncall0_addr_u16
	pcode_dispatch	$5c, __pcode_op_ncall1_addr_u16
	pcode_dispatch	$5d, __pcode_op_ncall2_addr_u16
	pcode_dispatch	$5e, __pcode_op_call3_u16
	pcode_dispatch	$5f, __pcode_op_ncall3_addr_u16
	pcode_dispatch	$60, __pcode_op_add
	pcode_dispatch	$61, __pcode_op_sub
	pcode_dispatch	$62, __pcode_op_and
	pcode_dispatch	$63, __pcode_op_or
	pcode_dispatch	$64, __pcode_op_xor
	pcode_dispatch	$65, __pcode_op_shl
	pcode_dispatch	$66, __pcode_op_shr
	pcode_dispatch	$67, __pcode_op_neg
	pcode_dispatch	$68, __pcode_op_bnot
	pcode_dispatch	$69, __pcode_op_lnot
	pcode_dispatch	$6a, __pcode_op_eq
	pcode_dispatch	$6b, __pcode_op_ne
	pcode_dispatch	$6c, __pcode_op_lt
	pcode_dispatch	$6d, __pcode_op_le
	pcode_dispatch	$6e, __pcode_op_gt
	pcode_dispatch	$6f, __pcode_op_ge
	jmp	__pcode_bad_opcode

__pcode_op_iconst_m1:
	set	v0, $ffff
	bsr	__pcode_push_v0
	b	__pcode_loop
__pcode_op_iconst_0:
	clr	v0
	bsr	__pcode_push_v0
	b	__pcode_loop
__pcode_op_iconst_1:
	set	v0, 1
	bsr	__pcode_push_v0
	b	__pcode_loop
__pcode_op_iconst_2:
	set	v0, 2
	bsr	__pcode_push_v0
	b	__pcode_loop
__pcode_op_iconst_s8:
	bsr	__pcode_fetch_s8
	bsr	__pcode_push_v0
	b	__pcode_loop
__pcode_op_iconst_u16:
	bsr	__pcode_fetch_u16
	bsr	__pcode_push_v0
	b	__pcode_loop

__pcode_op_drop:
	bsr	__pcode_pop_v0
	b	__pcode_loop

__pcode_op_dup:
	bsr	__pcode_pop_v0
	bsr	__pcode_push_v0
	bsr	__pcode_push_v0
	b	__pcode_loop

__pcode_op_swap:
	bsr	__pcode_pop_v0
	push	v0
	bsr	__pcode_pop_v0
	mov	v1, v0
	pop	v0
	bsr	__pcode_push_v0
	mov	v0, v1
	bsr	__pcode_push_v0
	b	__pcode_loop

__pcode_op_addi_s8:
	bsr	__pcode_fetch_s8
	mov	v1, v0
	bsr	__pcode_pop_v0
	add	v0, v0, v1
	bsr	__pcode_push_v0
	b	__pcode_loop
__pcode_op_subi_s8:
	bsr	__pcode_fetch_s8
	mov	v1, v0
	bsr	__pcode_pop_v0
	sub	v0, v0, v1
	bsr	__pcode_push_v0
	b	__pcode_loop
__pcode_op_eqi_s8:
	bsr	__pcode_fetch_s8
	mov	v1, v0
	bsr	__pcode_pop_v0
	beq	__pcode_true, v0, v1
	b	__pcode_false
__pcode_op_addi_u16:
	bsr	__pcode_fetch_u16
	mov	v1, v0
	bsr	__pcode_pop_v0
	add	v0, v0, v1
	bsr	__pcode_push_v0
	b	__pcode_loop

__pcode_op_llocal_0:
	ldr	v0, v4, 0
	bsr	__pcode_push_v0
	b	__pcode_loop
__pcode_op_llocal_1:
	ldr	v0, v4, 1
	bsr	__pcode_push_v0
	b	__pcode_loop
__pcode_op_llocal_2:
	ldr	v0, v4, 2
	bsr	__pcode_push_v0
	b	__pcode_loop
__pcode_op_llocal_3:
	ldr	v0, v4, 3
	bsr	__pcode_push_v0
	b	__pcode_loop
__pcode_op_slocal_0:
	bsr	__pcode_pop_v0
	str	v0, v4, 0
	b	__pcode_loop
__pcode_op_slocal_1:
	bsr	__pcode_pop_v0
	str	v0, v4, 1
	b	__pcode_loop
__pcode_op_slocal_2:
	bsr	__pcode_pop_v0
	str	v0, v4, 2
	b	__pcode_loop
__pcode_op_slocal_3:
	bsr	__pcode_pop_v0
	str	v0, v4, 3
	b	__pcode_loop
__pcode_op_llocal_s8:
	bsr	__pcode_fetch_s8
	add	v0, v4, v0
	ldr	v0, v0, 0
	bsr	__pcode_push_v0
	b	__pcode_loop
__pcode_op_slocal_s8:
	bsr	__pcode_fetch_s8
	add	v1, v4, v0
	bsr	__pcode_pop_v0
	str	v0, v1, 0
	b	__pcode_loop
__pcode_op_llocal_u16:
	bsr	__pcode_fetch_u16
	add	v0, v4, v0
	ldr	v0, v0, 0
	bsr	__pcode_push_v0
	b	__pcode_loop
__pcode_op_slocal_u16:
	bsr	__pcode_fetch_u16
	add	v1, v4, v0
	bsr	__pcode_pop_v0
	str	v0, v1, 0
	b	__pcode_loop
__pcode_op_addr_local_s8:
	bsr	__pcode_fetch_s8
	add	v0, v4, v0
	bsr	__pcode_push_v0
	b	__pcode_loop
__pcode_op_addr_local_u16:
	bsr	__pcode_fetch_u16
	add	v0, v4, v0
	bsr	__pcode_push_v0
	b	__pcode_loop

__pcode_op_lglobal_u16:
	bsr	__pcode_fetch_u16
	mov	v1, v0
	ldr	v0, v1, 0
	bsr	__pcode_push_v0
	b	__pcode_loop
__pcode_op_sglobal_u16:
	bsr	__pcode_fetch_u16
	mov	v1, v0
	bsr	__pcode_pop_v0
	str	v0, v1, 0
	b	__pcode_loop
__pcode_op_addr_global_u16:
	bsr	__pcode_fetch_u16
	bsr	__pcode_push_v0
	b	__pcode_loop
__pcode_op_lbyte:
	bsr	__pcode_pop_v0
	ldrl	v0, v0, 0
	seth	v0, 0
	bsr	__pcode_push_v0
	b	__pcode_loop
__pcode_op_sbyte:
	bsr	__pcode_pop_v0
	mov	v1, v0
	bsr	__pcode_pop_v0
	strl	v1, v0, 0
	b	__pcode_loop
__pcode_op_lword:
	bsr	__pcode_pop_v0
	ldr	v0, v0, 0
	bsr	__pcode_push_v0
	b	__pcode_loop
__pcode_op_sword:
	bsr	__pcode_pop_v0
	mov	v1, v0
	bsr	__pcode_pop_v0
	str	v1, v0, 0
	b	__pcode_loop

__pcode_op_jmp_s8:
	bsr	__pcode_fetch_s8
	add	v2, v2, v0
	b	__pcode_loop
__pcode_op_jmp_s16:
	bsr	__pcode_fetch_u16
	add	v2, v2, v0
	b	__pcode_loop
__pcode_op_jz_s8:
	bsr	__pcode_fetch_s8
	mov	v1, v0
	bsr	__pcode_pop_v0
	beq	__pcode_jz_s8_take, v0, 0
	b	__pcode_loop
__pcode_jz_s8_take:
	add	v2, v2, v1
	b	__pcode_loop
__pcode_op_jz_s16:
	bsr	__pcode_fetch_u16
	mov	v1, v0
	bsr	__pcode_pop_v0
	beq	__pcode_jz_s16_take, v0, 0
	b	__pcode_loop
__pcode_jz_s16_take:
	add	v2, v2, v1
	b	__pcode_loop
__pcode_op_jnz_s8:
	bsr	__pcode_fetch_s8
	mov	v1, v0
	bsr	__pcode_pop_v0
	bne	__pcode_jnz_s8_take, v0, 0
	b	__pcode_loop
__pcode_jnz_s8_take:
	add	v2, v2, v1
	b	__pcode_loop
__pcode_op_jnz_s16:
	bsr	__pcode_fetch_u16
	mov	v1, v0
	bsr	__pcode_pop_v0
	bne	__pcode_jnz_s16_take, v0, 0
	b	__pcode_loop
__pcode_jnz_s16_take:
	add	v2, v2, v1
	b	__pcode_loop

__pcode_op_call_u16:
	bsr	__pcode_fetch_u16
	set	v1, __pcode_call_target
	str	v0, v1, 0
	bsr	__pcode_fetch_u8
	set	v1, __pcode_call_argc
	str	v0, v1, 0
	b	__pcode_call_enter

__pcode_op_call0_u16:
	bsr	__pcode_fetch_u16
	set	v1, __pcode_call_target
	str	v0, v1, 0
	clr	v0
	set	v1, __pcode_call_argc
	str	v0, v1, 0
	b	__pcode_call_enter

__pcode_op_call1_u16:
	bsr	__pcode_fetch_u16
	set	v1, __pcode_call_target
	str	v0, v1, 0
	set	v0, 1
	set	v1, __pcode_call_argc
	str	v0, v1, 0
	b	__pcode_call_enter

__pcode_op_call2_u16:
	bsr	__pcode_fetch_u16
	set	v1, __pcode_call_target
	str	v0, v1, 0
	set	v0, 2
	set	v1, __pcode_call_argc
	str	v0, v1, 0
	b	__pcode_call_enter

__pcode_op_call3_u16:
	bsr	__pcode_fetch_u16
	set	v1, __pcode_call_target
	str	v0, v1, 0
	set	v0, 3
	set	v1, __pcode_call_argc
	str	v0, v1, 0
	b	__pcode_call_enter

__pcode_op_icall_u8:
	bsr	__pcode_fetch_u8
	set	v1, __pcode_call_argc
	str	v0, v1, 0
	bsr	__pcode_pop_v0
	set	v1, __pcode_call_target
	str	v0, v1, 0
	b	__pcode_call_enter

__pcode_call_enter:
	push	v4
	push	v2
	set	v0, PCODE_FRAME_SIZE
	add	v4, v4, v0
	set	v0, 4
	set	v1, __pcode_call_off
	str	v0, v1, 0
__pcode_call_args_loop:
	set	v1, __pcode_call_argc
	ldr	v0, v1, 0
	beq	__pcode_call_args_done, v0, 0
	sub	v0, v0, 1
	str	v0, v1, 0
	set	v1, __pcode_call_off
	ldr	v0, v1, 0
	add	v1, v4, v0
	bsr	__pcode_pop_v0
	str	v0, v1, 0
	set	v1, __pcode_call_off
	ldr	v0, v1, 0
	add	v0, v0, 2
	str	v0, v1, 0
	b	__pcode_call_args_loop
__pcode_call_args_done:
	set	v1, __pcode_depth
	ldr	v0, v1, 0
	add	v0, v0, 1
	str	v0, v1, 0
	set	v1, __pcode_call_target
	ldr	v0, v1, 0
	mov	v2, v0
	jmp	__pcode_loop

__pcode_op_ncall_u8:
	bsr	__pcode_fetch_u8
	set	v1, __pcode_ncall_id
	str	v0, v1, 0
	bsr	__pcode_fetch_u8
	set	v1, __pcode_ncall_argc
	str	v0, v1, 0
	set	v1, __pcode_ncall_id
	ldr	v0, v1, 0
	shl	v0, v0, 1
	set	v1, __pcd_native
	add	v1, v1, v0
	ldr	v0, v1, 0
	set	v1, __pcode_ncall_target
	str	v0, v1, 0
	b	__pcode_ncall_setup

__pcode_op_ncall_addr_u16:
	bsr	__pcode_fetch_u8
	set	v1, __pcode_ncall_argc
	str	v0, v1, 0
	b	__pcode_ncall_addr_fetch_target

__pcode_op_ncall0_addr_u16:
	set	v1, __pcode_ncall_argc
	set	v0, 0
	str	v0, v1, 0
	b	__pcode_ncall_addr_fetch_target

__pcode_op_ncall1_addr_u16:
	set	v1, __pcode_ncall_argc
	set	v0, 1
	str	v0, v1, 0
	b	__pcode_ncall_addr_fetch_target

__pcode_op_ncall2_addr_u16:
	set	v1, __pcode_ncall_argc
	set	v0, 2
	str	v0, v1, 0
	b	__pcode_ncall_addr_fetch_target

__pcode_op_ncall3_addr_u16:
	set	v1, __pcode_ncall_argc
	set	v0, 3
	str	v0, v1, 0

__pcode_ncall_addr_fetch_target:
	bsr	__pcode_fetch_u16
	set	v1, __pcode_ncall_target
	str	v0, v1, 0

__pcode_ncall_setup:
	set	v1, __pcode_ncall_argc
	ldr	v0, v1, 0
	shl	v0, v0, 1
	set	v1, __pcode_ncall_arg_bytes
	str	v0, v1, 0
	clr	v0
	set	v1, __pcode_ncall_off
	str	v0, v1, 0
__pcode_ncall_pop_loop:
	set	v1, __pcode_ncall_argc
	ldr	v0, v1, 0
	beq	__pcode_ncall_push_args, v0, 0
	sub	v0, v0, 1
	str	v0, v1, 0
	set	v1, __pcode_ncall_off
	ldr	v0, v1, 0
	set	v1, __pcode_ncall_args
	add	v1, v1, v0
	bsr	__pcode_pop_v0
	str	v0, v1, 0
	set	v1, __pcode_ncall_off
	ldr	v0, v1, 0
	add	v0, v0, 2
	str	v0, v1, 0
	b	__pcode_ncall_pop_loop
__pcode_ncall_push_args:
	set	v1, __pcode_ncall_off
	ldr	v0, v1, 0
	beq	__pcode_ncall_do_call, v0, 0
	sub	v0, v0, 2
	str	v0, v1, 0
	set	v1, __pcode_ncall_args
	add	v1, v1, v0
	ldr	v0, v1, 0
	push	v0
	b	__pcode_ncall_push_args
__pcode_ncall_do_call:
	set	v1, __pcode_saved_ip
	str	v2, v1, 0
	set	v1, __pcode_saved_stack
	str	v3, v1, 0
	set	v1, __pcode_saved_frame
	str	v4, v1, 0
	set	v1, __pcode_ncall_target
	ldr	v0, v1, 0
	add	lr, pc, 3
	mov	pc, v0
__pcode_ncall_return:
	set	v1, __pcode_ncall_retval
	str	v0, v1, 0
	set	v1, __pcode_ncall_arg_bytes
	ldr	v0, v1, 0
	add	sp, sp, v0
	set	v1, __pcode_saved_ip
	ldr	v2, v1, 0
	set	v1, __pcode_saved_stack
	ldr	v3, v1, 0
	set	v1, __pcode_saved_frame
	ldr	v4, v1, 0
	set	v1, __pcode_ncall_retval
	ldr	v0, v1, 0
	bsr	__pcode_push_v0
	jmp	__pcode_loop

__pcode_op_ret:
	bsr	__pcode_pop_v0
	set	v1, __pcode_depth
	ldr	v1, v1, 0
	beq	__pcode_done, v1, 0
	set	v1, __pcode_depth
	ldr	v1, v1, 0
	sub	v1, v1, 1
	set	v2, __pcode_depth
	str	v1, v2, 0
	pop	v2
	pop	v4
	bsr	__pcode_push_v0
	jmp	__pcode_loop

__pcode_op_add:
	bsr	__pcode_pop2
	add	v0, v0, v1
	bsr	__pcode_push_v0
	jmp	__pcode_loop
__pcode_op_sub:
	bsr	__pcode_pop2
	sub	v0, v0, v1
	bsr	__pcode_push_v0
	jmp	__pcode_loop
__pcode_op_and:
	bsr	__pcode_pop2
	and	v0, v0, v1
	bsr	__pcode_push_v0
	jmp	__pcode_loop
__pcode_op_or:
	bsr	__pcode_pop2
	or	v0, v0, v1
	bsr	__pcode_push_v0
	jmp	__pcode_loop
__pcode_op_xor:
	bsr	__pcode_pop2
	xor	v0, v0, v1
	bsr	__pcode_push_v0
	jmp	__pcode_loop
__pcode_op_shl:
	bsr	__pcode_pop2
	shl	v0, v0, v1
	bsr	__pcode_push_v0
	jmp	__pcode_loop
__pcode_op_shr:
	bsr	__pcode_pop2
	shr	v0, v0, v1
	bsr	__pcode_push_v0
	jmp	__pcode_loop
__pcode_op_neg:
	bsr	__pcode_pop_v0
	inv	v0, v0
	add	v0, v0, 1
	bsr	__pcode_push_v0
	jmp	__pcode_loop
__pcode_op_bnot:
	bsr	__pcode_pop_v0
	inv	v0, v0
	bsr	__pcode_push_v0
	jmp	__pcode_loop
__pcode_op_lnot:
	bsr	__pcode_pop_v0
	beq	__pcode_true, v0, 0
	b	__pcode_false
__pcode_op_eq:
	bsr	__pcode_pop2
	beq	__pcode_true, v0, v1
	b	__pcode_false
__pcode_op_ne:
	bsr	__pcode_pop2
	bne	__pcode_true, v0, v1
	b	__pcode_false
__pcode_op_lt:
	bsr	__pcode_pop2
	blt	__pcode_true, v0, v1
	b	__pcode_false
__pcode_op_le:
	bsr	__pcode_pop2
	ble	__pcode_true, v0, v1
	b	__pcode_false
__pcode_op_gt:
	bsr	__pcode_pop2
	bgt	__pcode_true, v0, v1
	b	__pcode_false
__pcode_op_ge:
	bsr	__pcode_pop2
	bge	__pcode_true, v0, v1
	b	__pcode_false

__pcode_true:
	set	v0, 1
	bsr	__pcode_push_v0
	jmp	__pcode_loop
__pcode_false:
	clr	v0
	bsr	__pcode_push_v0
	jmp	__pcode_loop

__pcode_fetch_u8:
	ldrl	v0, v2, 0
	seth	v0, 0
	add	v2, v2, 1
	rts

__pcode_fetch_s8:
	push	lr
	bsr	__pcode_fetch_u8
	set	v1, $80
	bitne	__pcode_fetch_s8_done, v0, v1
	seth	v0, $ff
__pcode_fetch_s8_done:
	pop	lr
	rts

__pcode_fetch_u16:
	push	lr
	bsr	__pcode_fetch_u8
	set	v1, __pcode_fetch_lo
	str	v0, v1, 0
	bsr	__pcode_fetch_u8
	shl	v0, v0, 8
	set	v1, __pcode_fetch_lo
	ldr	v1, v1, 0
	or	v0, v0, v1
	pop	lr
	rts

__pcode_push_v0:
	str	v0, v3, 0
	add	v3, v3, 2
	rts

__pcode_pop_v0:
	sub	v3, v3, 2
	ldr	v0, v3, 0
	rts

__pcode_pop2:
	push	lr
	bsr	__pcode_pop_v0
	mov	v1, v0
	bsr	__pcode_pop_v0
	pop	lr
	rts

__pcode_bad_opcode:
	set	v0, $bad0
	b	__test_halt

__pcode_done:
	b	__test_halt

__test_halt:
	b	__test_halt

	align	1
__pcode_fetch_lo:
	dw	0
__pcode_depth:
	dw	0
__pcode_call_argc:
	dw	0
__pcode_call_off:
	dw	0
__pcode_call_target:
	dw	0
__pcode_ncall_id:
	dw	0
__pcode_ncall_argc:
	dw	0
__pcode_ncall_arg_bytes:
	dw	0
__pcode_ncall_off:
	dw	0
__pcode_ncall_retval:
	dw	0
__pcode_ncall_target:
	dw	0
__pcode_saved_ip:
	dw	0
__pcode_saved_stack:
	dw	0
__pcode_saved_frame:
	dw	0
__pcode_ncall_args:
	ds	32
__pcd_native:
	dw	0

	align	1
__pcd_vstk:
__pcode_stack:
	ds	PCODE_STACK_BYTES
__pcd_vstkend:
__pcd_frames:
__pcode_frames:
	ds	PCODE_FRAME_SIZE
__pcd_frame0:
__pcode_frame0:
	ds	PCODE_FRAME_SIZE * PCODE_CALL_DEPTH
__pcd_frameend:
__pcd_nstk:
__pcode_native_stack:
	ds	512
__pcd_nstktop:
__pcode_native_stktop:

;
; FIS16 UART calculator for microemu / hc1200-mcu.
;
; Input uses reverse Polish notation. Tokens are whitespace-separated.
; Numbers are decimal, with an optional fractional part. Newline prints the top
; of the stack as fixed decimal with 4 fractional digits and clears the line.
; `q` halts.
;
; Example UART input:
;   1.5 2 *
;   q
;

include ../../asm/include/pseudo.inc
include ../../asm/include/devmap.inc

org $0000

	set	sp, runtime_stack
	bsr	calc_reset

main_loop:
	bsr	get_nonblank

	set	v4, 'q'
	eq	v0, v4
	b	main_not_q
	b	halt
main_not_q:

	eq	v0, 10
	b	main_not_lf
	b	finish_line
main_not_lf:
	eq	v0, 13
	b	main_not_cr
	b	finish_line
main_not_cr:

	set	v4, '-'
	eq	v0, v4
	b	main_not_minus
	b	handle_minus
main_not_minus:

	bsr	is_digit
	eq	v4, 0
	b	handle_operator
	b	parse_positive

parse_positive:
	set	v4, number_sign
	setl	v3, 0
	seth	v3, 0
	str	v3, v4, 0
	bsr	parse_number
	b	main_loop

handle_minus:
	bsr	getchar
	bsr	is_digit
	eq	v4, 0
	b	minus_operator
	b	parse_negative

parse_negative:
	set	v4, number_sign
	setl	v3, 1
	seth	v3, 0
	str	v3, v4, 0
	bsr	parse_number
	b	main_loop

minus_operator:
	bsr	ungetchar
	bsr	op_sub
	b	main_loop

handle_operator:
	set	v4, '+'
	eq	v0, v4
	b	main_not_add
	bsr	op_add
	b	main_loop
main_not_add:

	set	v4, '*'
	eq	v0, v4
	b	main_not_mul
	bsr	op_mul
	b	main_loop
main_not_mul:

	set	v4, '/'
	eq	v0, v4
	b	main_unknown
	bsr	op_div
	b	main_loop

main_unknown:
	bsr	print_error
	bsr	calc_reset
	b	main_loop

finish_line:
	set	v4, data_sp
	ldr	v4, v4, 0
	set	v3, data_stack
	eq	v4, v3
	b	finish_nonempty
	b	main_loop

finish_nonempty:
	sub	v4, v4, 4
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	bsr	print_fis16
	bsr	print_crlf
	bsr	calc_reset
	b	main_loop

halt:
	b	*

calc_reset proc
	set	v4, data_sp
	set	v3, data_stack
	str	v3, v4, 0
	set	v4, peek_valid
	setl	v3, 0
	seth	v3, 0
	str	v3, v4, 0
	rts
	endp

push_v1v0 proc
	set	v4, data_sp
	ldr	v4, v4, 0
	str	v0, v4, 0
	str	v1, v4, 2
	add	v4, v4, 4
	set	v3, data_sp
	str	v4, v3, 0
	rts
	endp

pop_rhs_lhs proc
	set	v0, data_sp
	ldr	v4, v0, 0
	sub	v4, v4, 4
	ldr	v2, v4, 0
	ldr	v3, v4, 2
	sub	v4, v4, 4
	str	v4, v0, 0
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	rts
	endp

op_add proc
	sub	sp, sp, 2
	str	lr, sp, 0
	bsr	pop_rhs_lhs
	jsr	fadd
	bsr	fis16_is_overflow
	eq	v4, 0
	b	op_add_overflow
	bsr	push_v1v0
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
op_add_overflow:
	bsr	signal_overflow
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

op_sub proc
	sub	sp, sp, 2
	str	lr, sp, 0
	bsr	pop_rhs_lhs
	jsr	fsub
	bsr	fis16_is_overflow
	eq	v4, 0
	b	op_sub_overflow
	bsr	push_v1v0
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
op_sub_overflow:
	bsr	signal_overflow
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

op_mul proc
	sub	sp, sp, 2
	str	lr, sp, 0
	bsr	pop_rhs_lhs
	jsr	fmul
	bsr	fis16_is_overflow
	eq	v4, 0
	b	op_mul_overflow
	bsr	push_v1v0
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
op_mul_overflow:
	bsr	signal_overflow
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

op_div proc
	sub	sp, sp, 2
	str	lr, sp, 0
	bsr	pop_rhs_lhs
	jsr	fdiv
	bsr	fis16_is_overflow
	eq	v4, 0
	b	op_div_overflow
	bsr	push_v1v0
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
op_div_overflow:
	bsr	signal_overflow
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

parse_number proc
	sub	sp, sp, 2
	str	lr, sp, 0

	set	v4, '0'
	sub	v0, v0, v4
	bsr	digit_to_fis16
	set	v4, number_value
	str	v0, v4, 0
	str	v1, v4, 2
	set	v4, scale_value
	set	v0, $8000
	set	v1, $0080
	str	v0, v4, 0
	str	v1, v4, 2
	set	v4, fraction_seen
	setl	v3, 0
	seth	v3, 0
	str	v3, v4, 0

parse_number_loop:
	bsr	getchar
	bsr	is_digit
	eq	v4, 0
	b	parse_number_not_digit
	b	parse_number_digit

parse_number_digit:
	set	v4, '0'
	sub	v0, v0, v4
	bsr	digit_to_fis16
	set	v4, digit_value
	str	v0, v4, 0
	str	v1, v4, 2

	set	v4, number_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	set	v2, $a000
	set	v3, $0083
	jsr	fmul
	bsr	fis16_is_overflow
	eq	v4, 0
	b	parse_number_overflow
	set	v4, digit_value
	ldr	v2, v4, 0
	ldr	v3, v4, 2
	jsr	fadd
	bsr	fis16_is_overflow
	eq	v4, 0
	b	parse_number_overflow
	set	v4, number_value
	str	v0, v4, 0
	str	v1, v4, 2

	set	v4, fraction_seen
	ldr	v4, v4, 0
	eq	v4, 0
	b	parse_number_scale
	b	parse_number_loop

parse_number_scale:
	set	v4, scale_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	set	v2, $a000
	set	v3, $0083
	jsr	fmul
	bsr	fis16_is_overflow
	eq	v4, 0
	b	parse_number_overflow
	set	v4, scale_value
	str	v0, v4, 0
	str	v1, v4, 2
	b	parse_number_loop

parse_number_not_digit:
	set	v4, '.'
	eq	v0, v4
	b	parse_number_done_char
	b	parse_number_dot

parse_number_dot:
	set	v4, fraction_seen
	ldr	v3, v4, 0
	eq	v3, 0
	b	parse_number_done_char
	setl	v3, 1
	seth	v3, 0
	str	v3, v4, 0
	b	parse_number_loop

parse_number_done_char:
	bsr	ungetchar

	set	v4, fraction_seen
	ldr	v4, v4, 0
	eq	v4, 0
	b	parse_number_apply_scale
	b	parse_number_after_scale

parse_number_apply_scale:
	set	v4, number_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	set	v4, scale_value
	ldr	v2, v4, 0
	ldr	v3, v4, 2
	jsr	fdiv
	bsr	fis16_is_overflow
	eq	v4, 0
	b	parse_number_overflow
	set	v4, number_value
	str	v0, v4, 0
	str	v1, v4, 2

parse_number_after_scale:
	set	v4, number_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	set	v4, number_sign
	ldr	v4, v4, 0
	eq	v4, 0
	b	parse_number_neg
	b	parse_number_push

parse_number_neg:
	eq	v0, 0
	b	parse_number_set_neg
	b	parse_number_push
parse_number_set_neg:
	setl	v4, 0
	seth	v4, $80
	or	v1, v1, v4

parse_number_push:
	bsr	push_v1v0
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts

parse_number_overflow:
	bsr	skip_token_tail
	bsr	signal_overflow
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

digit_to_fis16 proc
	shl	v0, v0, 2
	set	v4, digit_floats
	add	v4, v4, v0
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	rts
	endp

is_digit proc
	set	v4, '0'
	ltu	v0, v4
	b	is_digit_ge_0
	b	is_digit_no
is_digit_ge_0:
	set	v4, ':'
	ltu	v0, v4
	b	is_digit_no
	setl	v4, 0
	seth	v4, 0
	rts
is_digit_no:
	setl	v4, 1
	seth	v4, 0
	rts
	endp

fis16_is_overflow proc
	setl	v4, $ff
	seth	v4, $ff
	eq	v0, v4
	b	fis16_overflow_no
	mov	v4, v1
	set	v3, $00ff
	and	v4, v4, v3
	eq	v4, v3
	b	fis16_overflow_no
	setl	v4, 1
	seth	v4, 0
	rts
fis16_overflow_no:
	setl	v4, 0
	seth	v4, 0
	rts
	endp

skip_token_tail proc
	sub	sp, sp, 2
	str	lr, sp, 0
skip_token_tail_loop:
	bsr	getchar
	eq	v0, 10
	b	skip_token_tail_check_cr
	b	skip_token_tail_done
skip_token_tail_check_cr:
	eq	v0, 13
	b	skip_token_tail_check_space
	b	skip_token_tail_done
skip_token_tail_check_space:
	set	v4, ' '
	eq	v0, v4
	b	skip_token_tail_check_tab
	b	skip_token_tail_done
skip_token_tail_check_tab:
	eq	v0, 9
	b	skip_token_tail_loop
skip_token_tail_done:
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

get_nonblank proc
	sub	sp, sp, 2
	str	lr, sp, 0
get_nonblank_loop:
	bsr	getchar
	set	v4, ' '
	eq	v0, v4
	b	get_nonblank_not_space
	b	get_nonblank_loop
get_nonblank_not_space:
	eq	v0, 9
	b	get_nonblank_done
	b	get_nonblank_loop
get_nonblank_done:
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

getchar proc
	set	v4, peek_valid
	ldr	v0, v4, 0
	eq	v0, 0
	b	getchar_peek
	b	getchar_uart
getchar_peek:
	setl	v0, 0
	seth	v0, 0
	str	v0, v4, 0
	set	v4, peek_char
	ldr	v0, v4, 0
	rts

getchar_uart:
	set	v1, UART_ADDR
getchar_wait:
	ldrl	v0, v1, 0
	bitne	getchar_wait, v0, 1
	ldrl	v0, v1, 1
	seth	v0, 0
	rts
	endp

ungetchar proc
	set	v4, peek_char
	str	v0, v4, 0
	set	v4, peek_valid
	setl	v3, 1
	seth	v3, 0
	str	v3, v4, 0
	rts
	endp

putchar proc
	set	v4, char_tmp
	str	v0, v4, 0
	set	v1, UART_ADDR
putchar_wait:
	ldrl	v0, v1, 0
	biteq	putchar_wait, v0, 2
	set	v4, char_tmp
	ldr	v0, v4, 0
	strl	v0, v1, 1
	rts
	endp

print_crlf proc
	sub	sp, sp, 2
	str	lr, sp, 0
	setl	v0, 10
	seth	v0, 0
	bsr	putchar
	setl	v0, 13
	seth	v0, 0
	bsr	putchar
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

print_error proc
	sub	sp, sp, 2
	str	lr, sp, 0
	set	v2, error_msg
	bsr	print_string
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

print_overflow proc
	sub	sp, sp, 2
	str	lr, sp, 0
	set	v2, overflow_msg
	bsr	print_string
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

signal_overflow proc
	sub	sp, sp, 2
	str	lr, sp, 0
	bsr	print_overflow
	bsr	calc_reset
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

print_string proc
	sub	sp, sp, 2
	str	lr, sp, 0
print_string_loop:
	ldrl	v0, v2, 0
	seth	v0, 0
	eq	v0, 0
	b	print_string_char
	b	print_string_done
print_string_char:
	bsr	putchar
	add	v2, v2, 1
	b	print_string_loop
print_string_done:
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

print_fis16 proc
	sub	sp, sp, 2
	str	lr, sp, 0

	set	v4, print_value
	str	v0, v4, 0
	str	v1, v4, 2

	eq	v0, 0
	b	print_fis16_nonzero
	b	print_fis16_zero

print_fis16_nonzero:
	ge	v1, 0
	b	print_fis16_negative
	b	print_fis16_abs_ready

print_fis16_negative:
	setl	v0, '-'
	seth	v0, 0
	bsr	putchar
	set	v4, print_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	set	v4, $7fff
	and	v1, v1, v4

print_fis16_abs_ready:
	mov	v4, v1
	set	v3, $00ff
	and	v4, v4, v3
	set	v3, 128
	sub	v4, v4, v3
	sub	v4, v4, 15
	set	v3, shift_value
	str	v4, v3, 0

	setl	v1, 0
	seth	v1, 0
	set	v2, 10000
	setl	v3, 0
	seth	v3, 0
	jsr	u32_mul

	set	v4, shift_value
	ldr	v2, v4, 0
	ge	v2, 0
	b	print_fis16_shift_right
	b	print_fis16_shift_left

print_fis16_shift_left:
	jsr	u32_shl
	b	print_fis16_scaled

print_fis16_shift_right:
	setl	v4, 0
	seth	v4, 0
	sub	v2, v4, v2
	jsr	u32_shr

print_fis16_scaled:
	bsr	print_fixed4
	b	print_fis16_done

print_fis16_zero:
	set	v2, zero_fixed4
	bsr	print_string

print_fis16_done:
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

print_fixed4 proc
	sub	sp, sp, 2
	str	lr, sp, 0

	set	v2, 10000
	setl	v3, 0
	seth	v3, 0
	jsr	u32_div
	set	v4, print_rem
	str	v2, v4, 0
	bsr	print_u32

	setl	v0, '.'
	seth	v0, 0
	bsr	putchar

	set	v4, print_rem
	ldr	v0, v4, 0
	setl	v1, 0
	seth	v1, 0
	set	v2, 1000
	setl	v3, 0
	seth	v3, 0
	jsr	u32_div
	bsr	print_digit

	mov	v0, v2
	setl	v1, 0
	seth	v1, 0
	set	v2, 100
	setl	v3, 0
	seth	v3, 0
	jsr	u32_div
	bsr	print_digit

	mov	v0, v2
	setl	v1, 0
	seth	v1, 0
	set	v2, 10
	setl	v3, 0
	seth	v3, 0
	jsr	u32_div
	bsr	print_digit

	mov	v0, v2
	bsr	print_digit

	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

print_digit proc
	set	v4, '0'
	add	v0, v0, v4
	b	putchar
	endp

print_u32 proc
	sub	sp, sp, 2
	str	lr, sp, 0

	ne	v0, 0
	b	print_u32_check_hi
	b	print_u32_nonzero
print_u32_check_hi:
	ne	v1, 0
	b	print_u32_zero
	b	print_u32_nonzero

print_u32_zero:
	setl	v0, '0'
	seth	v0, 0
	bsr	putchar
	b	print_u32_done

print_u32_nonzero:
	set	v4, digit_buf
	set	v3, digit_ptr
	str	v4, v3, 0

print_u32_digit_loop:
	set	v4, print_value
	str	v0, v4, 0
	str	v1, v4, 2
	set	v2, 10
	setl	v3, 0
	seth	v3, 0
	jsr	u32_div

	set	v4, print_value
	str	v0, v4, 0
	str	v1, v4, 2

	set	v4, '0'
	add	v2, v2, v4
	set	v4, digit_ptr
	ldr	v4, v4, 0
	strl	v2, v4, 0
	add	v4, v4, 1
	set	v3, digit_ptr
	str	v4, v3, 0

	ne	v0, 0
	b	print_u32_check_qhi
	b	print_u32_digit_loop
print_u32_check_qhi:
	ne	v1, 0
	b	print_u32_digits_done
	b	print_u32_digit_loop

print_u32_digits_done:
	b	print_u32_output_loop

print_u32_output_loop:
	set	v4, digit_ptr
	ldr	v4, v4, 0
	set	v3, digit_buf
	eq	v4, v3
	b	print_u32_output_char
	b	print_u32_done
print_u32_output_char:
	sub	v4, v4, 1
	set	v3, digit_ptr
	str	v4, v3, 0
	ldrl	v0, v4, 0
	bsr	putchar
	b	print_u32_output_loop

print_u32_done:
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

include ../../asm/include/fis16.inc

align 1

data_sp:
	dw	0
peek_valid:
	dw	0
peek_char:
	dw	0
number_sign:
	dw	0
fraction_seen:
	dw	0
number_value:
	dw	0, 0
scale_value:
	dw	0, 0
digit_value:
	dw	0, 0
shift_value:
	dw	0
char_tmp:
	dw	0
print_value:
	dw	0, 0
print_rem:
	dw	0
digit_ptr:
	dw	0

digit_floats:
	dw	0, 0
	dw	$8000, $0080
	dw	$8000, $0081
	dw	$c000, $0081
	dw	$8000, $0082
	dw	$a000, $0082
	dw	$c000, $0082
	dw	$e000, $0082
	dw	$8000, $0083
	dw	$9000, $0083

error_msg:
	db	"ERR", 10, 13, 0
overflow_msg:
	db	"OVF", 10, 13, 0
zero_fixed4:
	db	"0.0000", 0

align 1
digit_buf:
	ds	12
data_stack:
	ds	128
	ds	160
runtime_stack:

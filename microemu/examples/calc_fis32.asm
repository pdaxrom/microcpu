;
; FIS32 UART calculator for microemu / hc1200-mcu.
;
; Input uses reverse Polish notation. Tokens are whitespace-separated.
; Numbers are decimal, with an optional fractional part and `e`/`E` exponent.
; Newline prints the top of the stack as fixed decimal or scientific notation
; with up to 7 significant digits and clears the line.
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
	bsr	print_fis32
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
	jsr	f32add
	bsr	fis32_is_overflow
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
	jsr	f32sub
	bsr	fis32_is_overflow
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
	jsr	f32mul
	bsr	fis32_is_overflow
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
	jsr	f32div
	bsr	fis32_is_overflow
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
	bsr	digit_to_fis32
	set	v4, number_value
	str	v0, v4, 0
	str	v1, v4, 2
	set	v4, scale_value
	setl	v0, 0
	seth	v0, 0
	set	v1, $4080
	str	v0, v4, 0
	str	v1, v4, 2
	set	v4, fraction_seen
	setl	v3, 0
	seth	v3, 0
	str	v3, v4, 0
	set	v4, exponent_value
	str	v3, v4, 0
	set	v4, exponent_sign
	str	v3, v4, 0
	set	v4, exponent_digits
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
	bsr	digit_to_fis32
	set	v4, digit_value
	str	v0, v4, 0
	str	v1, v4, 2

	set	v4, number_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	setl	v2, 0
	seth	v2, 0
	set	v3, $4220
	jsr	f32mul
	bsr	fis32_is_overflow
	eq	v4, 0
	b	parse_number_overflow
	set	v4, digit_value
	ldr	v2, v4, 0
	ldr	v3, v4, 2
	jsr	f32add
	bsr	fis32_is_overflow
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
	setl	v2, 0
	seth	v2, 0
	set	v3, $4220
	jsr	f32mul
	bsr	fis32_is_overflow
	eq	v4, 0
	b	parse_number_overflow
	set	v4, scale_value
	str	v0, v4, 0
	str	v1, v4, 2
	b	parse_number_loop

parse_number_not_digit:
	set	v4, '.'
	eq	v0, v4
	b	parse_number_check_exp
	b	parse_number_dot

parse_number_check_exp:
	set	v4, 'e'
	eq	v0, v4
	b	parse_number_check_exp_upper
	b	parse_number_exp
parse_number_check_exp_upper:
	set	v4, 'E'
	eq	v0, v4
	b	parse_number_done_char
	b	parse_number_exp

parse_number_dot:
	set	v4, fraction_seen
	ldr	v3, v4, 0
	eq	v3, 0
	b	parse_number_done_char
	setl	v3, 1
	seth	v3, 0
	str	v3, v4, 0
	b	parse_number_loop

parse_number_exp:
	set	v4, exponent_value
	setl	v3, 0
	seth	v3, 0
	str	v3, v4, 0
	set	v4, exponent_sign
	str	v3, v4, 0
	set	v4, exponent_digits
	str	v3, v4, 0

	bsr	getchar
	set	v4, '+'
	eq	v0, v4
	b	parse_number_exp_check_minus
	b	parse_number_exp_after_sign

parse_number_exp_check_minus:
	set	v4, '-'
	eq	v0, v4
	b	parse_number_exp_first_char
	set	v4, exponent_sign
	setl	v3, 1
	seth	v3, 0
	str	v3, v4, 0

parse_number_exp_after_sign:
	bsr	getchar
	b	parse_number_exp_first_char

parse_number_exp_loop:
	bsr	getchar
parse_number_exp_first_char:
	bsr	is_digit
	eq	v4, 0
	b	parse_number_exp_done_char
	b	parse_number_exp_digit

parse_number_exp_digit:
	set	v4, exponent_digits
	setl	v3, 1
	seth	v3, 0
	str	v3, v4, 0

	set	v4, '0'
	sub	v2, v0, v4
	set	v4, exponent_value
	ldr	v3, v4, 0
	set	v4, 26
	ltu	v3, v4
	b	parse_number_exp_clamp

	mov	v4, v3
	shl	v3, v3, 3
	shl	v4, v4, 1
	add	v3, v3, v4
	add	v3, v3, v2
	set	v4, 256
	ltu	v3, v4
	b	parse_number_exp_clamp
	set	v4, exponent_value
	str	v3, v4, 0
	b	parse_number_exp_loop

parse_number_exp_clamp:
	set	v4, exponent_value
	set	v3, 255
	str	v3, v4, 0
	b	parse_number_exp_loop

parse_number_exp_done_char:
	set	v4, exponent_digits
	ldr	v4, v4, 0
	ne	v4, 0
	b	parse_number_error
	b	parse_number_done_char

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
	jsr	f32div
	bsr	fis32_is_overflow
	eq	v4, 0
	b	parse_number_overflow
	set	v4, number_value
	str	v0, v4, 0
	str	v1, v4, 2

parse_number_after_scale:
	set	v4, exponent_value
	ldr	v4, v4, 0
	eq	v4, 0
	b	parse_number_apply_exp
	b	parse_number_after_exp

parse_number_apply_exp:
	set	v4, exponent_sign
	ldr	v4, v4, 0
	eq	v4, 0
	b	parse_number_exp_negative
	b	parse_number_exp_positive

parse_number_exp_positive:
	set	v4, exponent_value
	ldr	v4, v4, 0
	eq	v4, 0
	b	parse_number_exp_positive_body
	b	parse_number_after_exp
parse_number_exp_positive_body:
	set	v4, number_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	setl	v2, 0
	seth	v2, 0
	set	v3, $4220
	jsr	f32mul
	bsr	fis32_is_overflow
	eq	v4, 0
	b	parse_number_overflow
	set	v4, number_value
	str	v0, v4, 0
	str	v1, v4, 2
	set	v4, exponent_value
	ldr	v3, v4, 0
	sub	v3, v3, 1
	str	v3, v4, 0
	b	parse_number_exp_positive

parse_number_exp_negative:
	set	v4, exponent_value
	ldr	v4, v4, 0
	eq	v4, 0
	b	parse_number_exp_negative_body
	b	parse_number_after_exp
parse_number_exp_negative_body:
	set	v4, number_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	setl	v2, 0
	seth	v2, 0
	set	v3, $4220
	jsr	f32div
	set	v4, number_value
	str	v0, v4, 0
	str	v1, v4, 2
	set	v4, exponent_value
	ldr	v3, v4, 0
	sub	v3, v3, 1
	str	v3, v4, 0
	b	parse_number_exp_negative

parse_number_after_exp:
	set	v4, number_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	set	v4, number_sign
	ldr	v4, v4, 0
	eq	v4, 0
	b	parse_number_neg
	b	parse_number_push

parse_number_neg:
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
parse_number_error:
	bsr	ungetchar
	bsr	signal_error
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

digit_to_fis32 proc
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

fis32_is_overflow proc
	setl	v4, $ff
	seth	v4, $ff
	eq	v0, v4
	b	fis32_overflow_no
	mov	v4, v1
	set	v3, $7fff
	and	v4, v4, v3
	eq	v4, v3
	b	fis32_overflow_no
	setl	v4, 1
	seth	v4, 0
	rts
fis32_overflow_no:
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
	strl	v0, v1, 1
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

signal_error proc
	sub	sp, sp, 2
	str	lr, sp, 0
	bsr	print_error
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

print_fis32 proc
	sub	sp, sp, 2
	str	lr, sp, 0

	set	v4, print_value
	str	v0, v4, 0
	str	v1, v4, 2

	ne	v0, 0
	b	print_fis32_check_hi
	b	print_fis32_nonzero

print_fis32_check_hi:
	mov	v4, v1
	set	v3, $7fff
	and	v4, v4, v3
	ne	v4, 0
	b	print_fis32_zero
	b	print_fis32_nonzero

print_fis32_nonzero:
	ge	v1, 0
	b	print_fis32_negative
	b	print_fis32_abs_ready

print_fis32_negative:
	setl	v0, '-'
	seth	v0, 0
	bsr	putchar
	set	v4, print_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	set	v4, $7fff
	and	v1, v1, v4
	set	v4, print_value
	str	v0, v4, 0
	str	v1, v4, 2

print_fis32_abs_ready:
	set	v4, print_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	set	v2, $37bd
	set	v3, $3686
	bsr	f32c_ge_raw
	ne	v4, 0
	b	print_fis32_scientific

	set	v4, print_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	set	v2, $9680
	set	v3, $4c18
	bsr	f32c_ge_raw
	eq	v4, 0
	b	print_fis32_scientific
	bsr	print_fis32_fixed_value
	b	print_fis32_done

print_fis32_scientific:
	bsr	print_fis32_scientific_value
	b	print_fis32_done

print_fis32_zero:
	set	v2, zero_fixed2
	bsr	print_string

print_fis32_done:
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

f32c_ge_raw proc
	setl	v4, 0
	seth	v4, 0
	ltu	v1, v3
	b	f32c_ge_raw_hi_not_lt
	rts
f32c_ge_raw_hi_not_lt:
	ltu	v3, v1
	b	f32c_ge_raw_hi_eq
	setl	v4, 1
	rts
f32c_ge_raw_hi_eq:
	ltu	v0, v2
	b	f32c_ge_raw_true
	rts
f32c_ge_raw_true:
	setl	v4, 1
	rts
	endp

print_fis32_scientific_value proc
	sub	sp, sp, 2
	str	lr, sp, 0

	set	v4, sci_exp
	setl	v3, 0
	seth	v3, 0
	str	v3, v4, 0

print_fis32_sci_scale_down:
	set	v4, print_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	setl	v2, 0
	seth	v2, 0
	set	v3, $4220
	bsr	f32c_ge_raw
	eq	v4, 0
	b	print_fis32_sci_scale_down_body
	b	print_fis32_sci_scale_up

print_fis32_sci_scale_down_body:
	set	v4, print_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	setl	v2, 0
	seth	v2, 0
	set	v3, $4220
	jsr	f32div
	set	v4, print_value
	str	v0, v4, 0
	str	v1, v4, 2
	set	v4, sci_exp
	ldr	v3, v4, 0
	add	v3, v3, 1
	str	v3, v4, 0
	b	print_fis32_sci_scale_down

print_fis32_sci_scale_up:
	set	v4, print_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	setl	v2, 0
	seth	v2, 0
	set	v3, $4080
	bsr	f32c_ge_raw
	ne	v4, 0
	b	print_fis32_sci_scale_up_body
	b	print_fis32_sci_print

print_fis32_sci_scale_up_body:
	set	v4, print_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	setl	v2, 0
	seth	v2, 0
	set	v3, $4220
	jsr	f32mul
	set	v4, print_value
	str	v0, v4, 0
	str	v1, v4, 2
	set	v4, sci_exp
	ldr	v3, v4, 0
	sub	v3, v3, 1
	str	v3, v4, 0
	b	print_fis32_sci_scale_up

print_fis32_sci_print:
	bsr	print_fis32_fixed_value
	setl	v0, 'e'
	seth	v0, 0
	bsr	putchar
	set	v4, sci_exp
	ldr	v0, v4, 0
	bsr	print_i16
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

print_fis32_fixed_value proc
	sub	sp, sp, 2
	str	lr, sp, 0

	set	v4, print_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	bsr	f32c_abs_to_u32_floor
	ne	v0, 0
	b	print_fis32_fixed_floor_check_hi
	b	print_fis32_fixed_floor_nonzero
print_fis32_fixed_floor_check_hi:
	ne	v1, 0
	b	print_fis32_fixed_floor_zero
	b	print_fis32_fixed_floor_nonzero

print_fis32_fixed_floor_zero:
	set	v4, print_rem
	set	v2, 7
	str	v2, v4, 0
	b	print_fis32_fixed_round

print_fis32_fixed_floor_nonzero:
	bsr	u32_dec_digits
	set	v2, 7
	sub	v2, v2, v4
	ge	v2, 0
	b	print_fis32_fixed_no_frac
	b	print_fis32_fixed_store_frac_count
print_fis32_fixed_no_frac:
	setl	v2, 0
	seth	v2, 0
print_fis32_fixed_store_frac_count:
	set	v4, print_rem
	str	v2, v4, 0

print_fis32_fixed_round:
	set	v4, print_rem
	ldr	v4, v4, 0
	shl	v4, v4, 2
	set	v3, round_floats
	add	v3, v3, v4
	ldr	v2, v3, 0
	ldr	v3, v3, 2
	set	v4, print_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	jsr	f32add
	set	v4, print_value
	str	v0, v4, 0
	str	v1, v4, 2

	bsr	f32c_store_fraction
	set	v4, print_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	bsr	f32c_abs_to_u32_floor
	bsr	print_u32

	set	v4, frac_count
	set	v3, print_rem
	ldr	v2, v3, 0
	str	v2, v4, 0
	eq	v2, 0
	b	print_fis32_frac_setup
	b	print_fis32_fixed_done

print_fis32_frac_setup:
	set	v4, digit_ptr
	set	v3, digit_buf
	str	v3, v4, 0
	set	v4, frac_last
	str	v3, v4, 0

print_fis32_frac_loop:
	set	v4, frac_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	setl	v2, 0
	seth	v2, 0
	set	v3, $4220
	jsr	f32mul
	set	v4, frac_value
	str	v0, v4, 0
	str	v1, v4, 2

	bsr	f32c_abs_to_u32_floor
	set	v4, 10
	ltu	v0, v4
	b	print_fis32_digit_clamp
	b	print_fis32_digit_ready
print_fis32_digit_clamp:
	setl	v0, 9
	seth	v0, 0
print_fis32_digit_ready:
	set	v4, digit_int
	str	v0, v4, 0

	mov	v2, v0
	set	v4, '0'
	add	v2, v2, v4
	set	v4, digit_ptr
	ldr	v4, v4, 0
	strl	v2, v4, 0
	add	v4, v4, 1
	set	v3, digit_ptr
	str	v4, v3, 0
	eq	v0, 0
	b	print_fis32_frac_set_last
	b	print_fis32_frac_after_last
print_fis32_frac_set_last:
	set	v3, frac_last
	str	v4, v3, 0
print_fis32_frac_after_last:

	set	v4, digit_int
	ldr	v0, v4, 0
	bsr	digit_to_fis32
	mov	v2, v0
	mov	v3, v1
	set	v4, frac_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	jsr	f32sub
	ge	v1, 0
	b	print_fis32_frac_zero
	b	print_fis32_frac_store
print_fis32_frac_zero:
	setl	v0, 0
	seth	v0, 0
	setl	v1, 0
	seth	v1, 0
print_fis32_frac_store:
	set	v4, frac_value
	str	v0, v4, 0
	str	v1, v4, 2

	set	v4, frac_count
	ldr	v2, v4, 0
	sub	v2, v2, 1
	str	v2, v4, 0
	eq	v2, 0
	b	print_fis32_frac_loop

	set	v4, frac_last
	ldr	v4, v4, 0
	set	v3, digit_buf
	eq	v4, v3
	b	print_fis32_frac_output_setup
	b	print_fis32_fixed_done

print_fis32_frac_output_setup:
	setl	v0, '.'
	seth	v0, 0
	bsr	putchar
	set	v4, digit_ptr
	set	v3, digit_buf
	str	v3, v4, 0

print_fis32_frac_output_loop:
	set	v4, digit_ptr
	ldr	v4, v4, 0
	set	v3, frac_last
	ldr	v3, v3, 0
	eq	v4, v3
	b	print_fis32_frac_output_char
	b	print_fis32_fixed_done
print_fis32_frac_output_char:
	ldrl	v0, v4, 0
	seth	v0, 0
	bsr	putchar
	set	v3, digit_ptr
	ldr	v4, v3, 0
	add	v4, v4, 1
	str	v4, v3, 0
	b	print_fis32_frac_output_loop

print_fis32_fixed_done:
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

f32c_abs_to_u32_floor proc
	sub	sp, sp, 2
	str	lr, sp, 0

	set	v4, $7fff
	and	v4, v1, v4
	ne	v4, 0
	b	f32c_floor_zero
	b	f32c_floor_nonzero

f32c_floor_zero:
	setl	v0, 0
	seth	v0, 0
	setl	v1, 0
	seth	v1, 0
	b	f32c_floor_return

f32c_floor_nonzero:
	mov	v4, v1
	shr	v4, v4, 7
	set	v3, $00ff
	and	v4, v4, v3
	set	v3, 128
	sub	v4, v4, v3
	set	v3, 24
	sub	v4, v4, v3
	set	v3, shift_value
	str	v4, v3, 0

	set	v4, $007f
	and	v1, v1, v4
	set	v4, $0080
	or	v1, v1, v4

	set	v4, shift_value
	ldr	v2, v4, 0
	ge	v2, 0
	b	f32c_floor_shift_right
	b	f32c_floor_shift_left

f32c_floor_shift_left:
	jsr	u32_shl
	b	f32c_floor_return

f32c_floor_shift_right:
	setl	v4, 0
	seth	v4, 0
	sub	v2, v4, v2
	jsr	u32_shr
	b	f32c_floor_return

f32c_floor_return:
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

f32c_store_fraction proc
	sub	sp, sp, 2
	str	lr, sp, 0

	set	v4, print_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	mov	v4, v1
	shr	v4, v4, 7
	set	v3, $00ff
	and	v4, v4, v3
	set	v3, 152
	sub	v2, v3, v4
	set	v4, rem_shift
	str	v2, v4, 0

	set	v4, 1
	ge	v2, v4
	b	f32c_fraction_zero
	b	f32c_fraction_some

f32c_fraction_zero:
	setl	v0, 0
	seth	v0, 0
	setl	v1, 0
	seth	v1, 0
	b	f32c_fraction_store

f32c_fraction_some:
	set	v4, 24
	ltu	v2, v4
	b	f32c_fraction_all
	b	f32c_fraction_partial

f32c_fraction_all:
	set	v4, print_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	b	f32c_fraction_store

f32c_fraction_partial:
	set	v4, print_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	set	v4, $007f
	and	v1, v1, v4
	set	v4, $0080
	or	v1, v1, v4
	set	v4, mant_value
	str	v0, v4, 0
	str	v1, v4, 2

	set	v4, rem_shift
	ldr	v2, v4, 0
	jsr	u32_shr
	set	v4, rem_shift
	ldr	v2, v4, 0
	jsr	u32_shl
	set	v4, restored_value
	str	v0, v4, 0
	str	v1, v4, 2

	set	v4, mant_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	set	v4, restored_value
	ldr	v2, v4, 0
	ldr	v3, v4, 2
	jsr	u32_sub
	bsr	f32c_pack_fraction_remainder

f32c_fraction_store:
	set	v4, frac_value
	str	v0, v4, 0
	str	v1, v4, 2
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

f32c_pack_fraction_remainder proc
	sub	sp, sp, 2
	str	lr, sp, 0

	ne	v0, 0
	b	f32c_pack_rem_check_hi
	b	f32c_pack_rem_nonzero
f32c_pack_rem_check_hi:
	ne	v1, 0
	b	f32c_pack_rem_zero
	b	f32c_pack_rem_nonzero

f32c_pack_rem_zero:
	setl	v0, 0
	seth	v0, 0
	setl	v1, 0
	seth	v1, 0
	b	f32c_pack_rem_return

f32c_pack_rem_nonzero:
	set	v4, rem_shift
	ldr	v4, v4, 0
	set	v3, 152
	sub	v4, v3, v4
	set	v3, shift_value
	str	v4, v3, 0

f32c_pack_rem_norm:
	set	v4, $0080
	and	v4, v1, v4
	eq	v4, 0
	b	f32c_pack_rem_done
	jsr	u32_shl1
	set	v4, shift_value
	ldr	v3, v4, 0
	sub	v3, v3, 1
	str	v3, v4, 0
	b	f32c_pack_rem_norm

f32c_pack_rem_done:
	set	v4, shift_value
	ldr	v4, v4, 0
	set	v3, 1
	ge	v4, v3
	b	f32c_pack_rem_zero
	b	f32c_pack_rem_exp_ok
f32c_pack_rem_exp_ok:
	shl	v4, v4, 7
	set	v3, $007f
	and	v1, v1, v3
	or	v1, v1, v4
	b	f32c_pack_rem_return

f32c_pack_rem_return:
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

print_digit proc
	set	v4, '0'
	add	v0, v0, v4
	b	putchar
	endp

print_i16 proc
	sub	sp, sp, 4
	str	lr, sp, 0
	str	v0, sp, 2
	ge	v0, 0
	b	print_i16_negative
	b	print_i16_abs_ready
print_i16_negative:
	setl	v0, '-'
	seth	v0, 0
	bsr	putchar
	ldr	v0, sp, 2
	setl	v4, 0
	seth	v4, 0
	sub	v0, v4, v0
print_i16_abs_ready:
	setl	v1, 0
	seth	v1, 0
	bsr	print_u32
	ldr	lr, sp, 0
	add	sp, sp, 4
	rts
	endp

u32_dec_digits proc
	sub	sp, sp, 4
	str	lr, sp, 0
	setl	v4, 0
	seth	v4, 0
	str	v4, sp, 2
u32_dec_digits_loop:
	ldr	v4, sp, 2
	add	v4, v4, 1
	str	v4, sp, 2
	set	v2, 10
	setl	v3, 0
	seth	v3, 0
	jsr	u32_div
	ne	v0, 0
	b	u32_dec_digits_check_hi
	b	u32_dec_digits_loop
u32_dec_digits_check_hi:
	ne	v1, 0
	b	u32_dec_digits_done
	b	u32_dec_digits_loop
u32_dec_digits_done:
	ldr	v4, sp, 2
	ldr	lr, sp, 0
	add	sp, sp, 4
	rts
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

include ../../asm/include/fis32.inc

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
exponent_sign:
	dw	0
exponent_value:
	dw	0
exponent_digits:
	dw	0
number_value:
	dw	0, 0
scale_value:
	dw	0, 0
digit_value:
	dw	0, 0
digit_int:
	dw	0
shift_value:
	dw	0
rem_shift:
	dw	0
char_tmp:
	dw	0
print_value:
	dw	0, 0
print_rem:
	dw	0
frac_value:
	dw	0, 0
mant_value:
	dw	0, 0
restored_value:
	dw	0, 0
frac_count:
	dw	0
sci_exp:
	dw	0
digit_ptr:
	dw	0
frac_last:
	dw	0

digit_floats:
	dw	0, 0
	dw	0, $4080
	dw	0, $4100
	dw	0, $4140
	dw	0, $4180
	dw	0, $41a0
	dw	0, $41c0
	dw	0, $41e0
	dw	0, $4200
	dw	0, $4210

round_floats:
	dw	$0000, $4000
	dw	$cccc, $3e4c
	dw	$d70a, $3ca3
	dw	$126e, $3b03
	dw	$b717, $3951
	dw	$c5ac, $37a7
	dw	$37bd, $3606
	dw	$d959, $3480

error_msg:
	db	"ERR", 10, 13, 0
overflow_msg:
	db	"OVF", 10, 13, 0
zero_fixed2:
	db	"0", 0

align 1
digit_buf:
	ds	12
data_stack:
	ds	40
	ds	96
runtime_stack:

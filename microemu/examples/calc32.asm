;
; 32-bit UART calculator for microemu / hc1200-mcu.
;
; Input uses reverse Polish notation. Tokens are whitespace-separated.
; Newline prints the top of the stack as signed decimal and clears the line.
; `q` halts, which is useful for --stop-on-self-branch in the emulator.
;
; Operators:
;   +  signed/unsigned add modulo 2^32
;   -  signed/unsigned subtract modulo 2^32
;   *  low 32 bits of product
;   /  signed division
;   l  logical left shift by count
;   r  logical right shift by count
;   a  arithmetic right shift by count
;
; Example UART input:
;   12 34 +
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
	b	main_not_div
	bsr	op_div
	b	main_loop
main_not_div:

	set	v4, 'l'
	eq	v0, v4
	b	main_not_shl
	bsr	op_shl
	b	main_loop
main_not_shl:

	set	v4, 'r'
	eq	v0, v4
	b	main_not_shr
	bsr	op_shr
	b	main_loop
main_not_shr:

	set	v4, 'a'
	eq	v0, v4
	b	main_unknown
	bsr	op_sar
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
	bsr	print_i32
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
	bsr	i32_add
	bsr	push_v1v0
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

op_sub proc
	sub	sp, sp, 2
	str	lr, sp, 0
	bsr	pop_rhs_lhs
	bsr	i32_sub
	bsr	push_v1v0
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

op_mul proc
	sub	sp, sp, 2
	str	lr, sp, 0
	bsr	pop_rhs_lhs
	bsr	i32_mul
	bsr	push_v1v0
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

op_div proc
	sub	sp, sp, 2
	str	lr, sp, 0
	bsr	pop_rhs_lhs
	bsr	i32_div
	bsr	push_v1v0
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

op_shl proc
	sub	sp, sp, 2
	str	lr, sp, 0
	bsr	pop_rhs_lhs
	bsr	u32_shl
	bsr	push_v1v0
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

op_shr proc
	sub	sp, sp, 2
	str	lr, sp, 0
	bsr	pop_rhs_lhs
	bsr	u32_shr
	bsr	push_v1v0
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

op_sar proc
	sub	sp, sp, 2
	str	lr, sp, 0
	bsr	pop_rhs_lhs
	bsr	i32_sar
	bsr	push_v1v0
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

parse_number proc
	sub	sp, sp, 2
	str	lr, sp, 0

	set	v4, '0'
	sub	v0, v0, v4
	set	v4, number_value
	str	v0, v4, 0
	setl	v3, 0
	seth	v3, 0
	str	v3, v4, 2

parse_number_loop:
	bsr	getchar
	bsr	is_digit
	eq	v4, 0
	b	parse_number_done_char
	b	parse_number_digit

parse_number_digit:
	set	v4, '0'
	sub	v0, v0, v4
	set	v4, digit_value
	str	v0, v4, 0

	set	v4, number_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	set	v2, 10
	seth	v3, 0
	bsr	u32_mul
	set	v4, digit_value
	ldr	v2, v4, 0
	setl	v3, 0
	seth	v3, 0
	bsr	u32_add
	set	v4, number_value
	str	v0, v4, 0
	str	v1, v4, 2
	b	parse_number_loop

parse_number_done_char:
	bsr	ungetchar
	set	v4, number_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2

	set	v4, number_sign
	ldr	v4, v4, 0
	eq	v4, 0
	b	parse_number_neg
	b	parse_number_push

parse_number_neg:
	bsr	u32_neg

parse_number_push:
	bsr	push_v1v0
	ldr	lr, sp, 0
	add	sp, sp, 2
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

print_i32 proc
	sub	sp, sp, 2
	str	lr, sp, 0

	set	v4, print_value
	str	v0, v4, 0
	str	v1, v4, 2

	ge	v1, 0
	b	print_i32_negative
	b	print_i32_abs_ready

print_i32_negative:
	setl	v0, '-'
	seth	v0, 0
	bsr	putchar
	set	v4, print_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	bsr	u32_neg
	set	v4, print_value
	str	v0, v4, 0
	str	v1, v4, 2

print_i32_abs_ready:
	set	v4, print_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	ne	v0, 0
	b	print_i32_check_hi
	b	print_i32_nonzero
print_i32_check_hi:
	ne	v1, 0
	b	print_i32_zero
	b	print_i32_nonzero

print_i32_zero:
	setl	v0, '0'
	seth	v0, 0
	bsr	putchar
	b	print_i32_done

print_i32_nonzero:
	set	v4, digit_buf
	set	v3, digit_ptr
	str	v4, v3, 0

print_i32_digit_loop:
	set	v4, print_value
	ldr	v0, v4, 0
	ldr	v1, v4, 2
	set	v2, 10
	setl	v3, 0
	seth	v3, 0
	bsr	u32_div

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
	b	print_i32_check_qhi
	b	print_i32_digit_loop
print_i32_check_qhi:
	ne	v1, 0
	b	print_i32_digits_done
	b	print_i32_digit_loop

print_i32_digits_done:
	b	print_i32_output_loop

print_i32_output_loop:
	set	v4, digit_ptr
	ldr	v4, v4, 0
	set	v3, digit_buf
	eq	v4, v3
	b	print_i32_output_char
	b	print_i32_done
print_i32_output_char:
	sub	v4, v4, 1
	set	v3, digit_ptr
	str	v4, v3, 0
	ldrl	v0, v4, 0
	bsr	putchar
	b	print_i32_output_loop

print_i32_done:
	ldr	lr, sp, 0
	add	sp, sp, 2
	rts
	endp

include ../../asm/include/int32.inc

align 1

data_sp:
	dw	0
peek_valid:
	dw	0
peek_char:
	dw	0
number_sign:
	dw	0
number_value:
	dw	0, 0
digit_value:
	dw	0
char_tmp:
	dw	0
print_value:
	dw	0, 0
digit_ptr:
	dw	0

error_msg:
	db	"ERR", 10, 13, 0

align 1
digit_buf:
	ds	12
data_stack:
	ds	128
	ds	128
runtime_stack:

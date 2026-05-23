;
; Minimal hosted runtime for p-code selfhost execution smoke.
;
; This is not a full stdio implementation.  It maps stdin/stdout/stderr to the
; board UART and provides just enough C library surface for the split Small-C
; tools to start under microemu.  UART RX byte 0x04 is treated as EOF.
;

include ../../asm/include/pseudo.inc

extern __pcd_gend

public _stdin
public _stdout
public _stderr
public _calloc
public _fopen
public _fclose
public _fgetc
public _fgets
public _fputc
public _fputs
public _exit
public _toupper
public _isdigit
public _isalpha
public _isxdigit
public _strcpy
public _strncpy
public _memset
public __hst_lasterr
public __hst_allocsz
public __hst_hstart
public __hst_hcur
public __hst_hend
public __hst_service
public __hst_fhandle

HOSTED_UART_ADDR	equ	$ffe0
HOSTED_HEAP_LIMIT	equ	$fde0
HOSTED_EOF		equ	$ffff
HOSTED_EOT		equ	$04
HOSTED_SVC_CALLOC	equ	1

_stdin:
	dw	0
_stdout:
	dw	1
_stderr:
	dw	2
__hosted_hex_tmp:
	dw	0
__hst_lasterr:
	dw	0
__hst_allocsz:
	dw	0
__hst_hstart:
	dw	0
__hst_hcur:
	dw	0
__hst_hend:
	dw	HOSTED_HEAP_LIMIT
__hst_service:
	dw	0
__hst_fhandle:
	dw	0
__hosted_heap_ptr:
	dw	0
__hosted_fgets_buf:
	dw	0

_calloc:
	ldr	v0, sp, 4
	ldr	v1, sp, 2
	push	lr
	jsr	__hosted_mul_u16
	mov	v2, v0
	set	v1, __hst_allocsz
	str	v2, v1, 0
	set	v1, __hst_service
	set	v0, HOSTED_SVC_CALLOC
	str	v0, v1, 0
	set	v1, __hst_lasterr
	clr	v0
	str	v0, v1, 0
	set	v1, __hosted_heap_ptr
	ldr	v0, v1, 0
	bne	__calloc_have_heap, v0, 0
	set	v0, __pcd_gend
	add	v0, v0, 1
	set	v3, $fffe
	and	v0, v0, v3
	set	v1, __hst_hstart
	str	v0, v1, 0
__calloc_have_heap:
	set	v1, __hst_hcur
	str	v0, v1, 0
	mov	v3, v0
	add	v0, v0, v2
	bltu	__calloc_overflow, v0, v3
	set	v1, HOSTED_HEAP_LIMIT
	bgtu	__calloc_overflow, v0, v1
	set	v1, __hosted_heap_ptr
	str	v0, v1, 0
	set	v1, __hst_hcur
	str	v0, v1, 0
	mov	v0, v3
__calloc_zero_loop:
	beq	__calloc_done, v2, 0
	clr	v1
	strl	v1, v0, 0
	add	v0, v0, 1
	sub	v2, v2, 1
	b	__calloc_zero_loop
__calloc_done:
	mov	v0, v3
	pop	lr
	rts
__calloc_overflow:
	set	v0, $ca10
	set	v1, __hst_lasterr
	str	v0, v1, 0
	set	v1, __hst_hcur
	str	v3, v1, 0
	set	v1, __hst_hend
	set	v0, HOSTED_HEAP_LIMIT
	str	v0, v1, 0
	set	v1, __hst_fhandle
	clr	v0
	str	v0, v1, 0
	set	v0, $ca10
	jsr	__hosted_report_heap
	set	v0, $ca10
	b	__hosted_halt

_fopen:
	clr	v0
	rts

_fclose:
	clr	v0
	rts

_fgetc:
	b	__hosted_getc

_fgets:
	ldr	v0, sp, 6
	ldr	v1, sp, 4
	push	lr
	set	v2, __hosted_fgets_buf
	str	v0, v2, 0
	beq	__fgets_empty, v1, 0
	sub	v1, v1, 1
	beq	__fgets_terminate, v1, 0
	mov	v3, v0
__fgets_loop:
	beq	__fgets_terminate_at_ptr, v1, 0
	push	v1
	push	v3
	bsr	__hosted_getc
	mov	v2, v0
	pop	v3
	pop	v1
	set	v0, HOSTED_EOF
	beq	__fgets_eof, v2, v0
	strl	v2, v3, 0
	add	v3, v3, 1
	sub	v1, v1, 1
	set	v0, 10
	beq	__fgets_terminate_at_ptr, v2, v0
	b	__fgets_loop
__fgets_eof:
	set	v0, __hosted_fgets_buf
	ldr	v0, v0, 0
	beq	__fgets_empty, v3, v0
__fgets_terminate_at_ptr:
	clr	v0
	strl	v0, v3, 0
	set	v0, __hosted_fgets_buf
	ldr	v0, v0, 0
	pop	lr
	rts
__fgets_terminate:
	ldr	v3, sp, 6
	b	__fgets_terminate_at_ptr
__fgets_empty:
	clr	v0
	pop	lr
	rts

_fputc:
	ldr	v0, sp, 4
	seth	v0, 0
	mov	v3, v0
	push	lr
	bsr	__hosted_putc
	mov	v0, v3
	pop	lr
	rts

_fputs:
	ldr	v3, sp, 4
	push	lr
__fputs_loop:
	ldrl	v0, v3, 0
	seth	v0, 0
	beq	__fputs_done, v0, 0
	bsr	__hosted_putc
	add	v3, v3, 1
	b	__fputs_loop
__fputs_done:
	clr	v0
	pop	lr
	rts

_exit:
	ldr	v0, sp, 2
	b	__hosted_halt

_toupper:
	ldr	v0, sp, 2
	seth	v0, 0
	set	v1, 'a'
	blt	__toupper_done, v0, v1
	set	v1, 'z'
	bgt	__toupper_done, v0, v1
	set	v1, 32
	sub	v0, v0, v1
__toupper_done:
	rts

_isdigit:
	ldr	v0, sp, 2
	seth	v0, 0
	set	v1, '0'
	blt	__hosted_false, v0, v1
	set	v1, '9'
	bgt	__hosted_false, v0, v1
	b	__hosted_true

_isalpha:
	ldr	v0, sp, 2
	seth	v0, 0
	set	v1, 'A'
	blt	__isalpha_lower, v0, v1
	set	v1, 'Z'
	ble	__hosted_true, v0, v1
__isalpha_lower:
	set	v1, 'a'
	blt	__hosted_false, v0, v1
	set	v1, 'z'
	ble	__hosted_true, v0, v1
	b	__hosted_false

_isxdigit:
	ldr	v0, sp, 2
	seth	v0, 0
	set	v1, '0'
	blt	__isxdigit_upper, v0, v1
	set	v1, '9'
	ble	__hosted_true, v0, v1
__isxdigit_upper:
	set	v1, 'A'
	blt	__isxdigit_lower, v0, v1
	set	v1, 'F'
	ble	__hosted_true, v0, v1
__isxdigit_lower:
	set	v1, 'a'
	blt	__hosted_false, v0, v1
	set	v1, 'f'
	ble	__hosted_true, v0, v1
	b	__hosted_false

_strcpy:
	ldr	v0, sp, 4
	ldr	v1, sp, 2
	mov	v3, v0
__strcpy_loop:
	ldrl	v2, v1, 0
	strl	v2, v0, 0
	add	v0, v0, 1
	add	v1, v1, 1
	bne	__strcpy_loop, v2, 0
	mov	v0, v3
	rts

_strncpy:
	ldr	v0, sp, 6
	ldr	v1, sp, 4
	ldr	v2, sp, 2
	mov	v3, v0
__strncpy_copy:
	beq	__strncpy_done, v2, 0
	ldrl	v4, v1, 0
	strl	v4, v0, 0
	add	v0, v0, 1
	add	v1, v1, 1
	sub	v2, v2, 1
	beq	__strncpy_pad, v4, 0
	b	__strncpy_copy
__strncpy_pad:
	beq	__strncpy_done, v2, 0
	clr	v4
	strl	v4, v0, 0
	add	v0, v0, 1
	sub	v2, v2, 1
	b	__strncpy_pad
__strncpy_done:
	mov	v0, v3
	rts

_memset:
	ldr	v0, sp, 6
	ldr	v1, sp, 4
	ldr	v2, sp, 2
	seth	v1, 0
	mov	v3, v0
__memset_loop:
	beq	__memset_done, v2, 0
	strl	v1, v0, 0
	add	v0, v0, 1
	sub	v2, v2, 1
	b	__memset_loop
__memset_done:
	mov	v0, v3
	rts

__hosted_getc:
	set	v1, HOSTED_UART_ADDR
__hosted_getc_wait:
	ldrl	v2, v1, 0
	bitne	__hosted_getc_wait, v2, 1
	ldrl	v0, v1, 1
	seth	v0, 0
	set	v1, HOSTED_EOT
	beq	__hosted_getc_eof, v0, v1
	rts
__hosted_getc_eof:
	set	v0, HOSTED_EOF
	rts

__hosted_putc:
	set	v1, HOSTED_UART_ADDR
__hosted_putc_wait:
	ldrl	v2, v1, 0
	biteq	__hosted_putc_wait, v2, 2
	strl	v0, v1, 1
	rts

__hosted_report_heap:
	push	lr
	set	v0, 10
	jsr	__hosted_putc
	set	v0, 'H'
	jsr	__hosted_putc
	set	v0, 'D'
	jsr	__hosted_putc
	set	v0, ' '
	jsr	__hosted_putc
	set	v1, __hst_lasterr
	ldr	v0, v1, 0
	jsr	__hosted_put_hex
	set	v0, ' '
	jsr	__hosted_putc
	set	v1, __hst_allocsz
	ldr	v0, v1, 0
	jsr	__hosted_put_hex
	set	v0, ' '
	jsr	__hosted_putc
	set	v1, __hst_hcur
	ldr	v0, v1, 0
	jsr	__hosted_put_hex
	set	v0, ' '
	jsr	__hosted_putc
	set	v1, __hst_hstart
	ldr	v0, v1, 0
	jsr	__hosted_put_hex
	set	v0, ' '
	jsr	__hosted_putc
	set	v1, __hst_hend
	ldr	v0, v1, 0
	jsr	__hosted_put_hex
	set	v0, ' '
	jsr	__hosted_putc
	set	v1, __hst_service
	ldr	v0, v1, 0
	jsr	__hosted_put_hex
	set	v0, 10
	jsr	__hosted_putc
	pop	lr
	rts

__hosted_put_hex:
	push	lr
	set	v1, __hosted_hex_tmp
	str	v0, v1, 0
	set	v2, 12
__hosted_put_hex_loop:
	set	v1, __hosted_hex_tmp
	ldr	v0, v1, 0
	shr	v0, v0, v2
	and	v0, v0, 15
	set	v1, 10
	blt	__hosted_put_hex_digit, v0, v1
	set	v1, 55
	add	v0, v0, v1
	b	__hosted_put_hex_emit
__hosted_put_hex_digit:
	set	v1, 48
	add	v0, v0, v1
__hosted_put_hex_emit:
	push	v2
	jsr	__hosted_putc
	pop	v2
	beq	__hosted_put_hex_done, v2, 0
	sub	v2, v2, 4
	b	__hosted_put_hex_loop
__hosted_put_hex_done:
	pop	lr
	rts

__hosted_mul_u16:
	clr	v2
__hosted_mul_loop:
	beq	__hosted_mul_done, v1, 0
	and	v3, v1, 1
	beq	__hosted_mul_skip, v3, 0
	add	v2, v2, v0
__hosted_mul_skip:
	shl	v0, v0, 1
	shr	v1, v1, 1
	b	__hosted_mul_loop
__hosted_mul_done:
	mov	v0, v2
	rts

__hosted_true:
	set	v0, 1
	rts
__hosted_false:
	clr	v0
	rts

__hosted_halt:
	b	__hosted_halt

;
; Minimal Small-C string/runtime routines.
;

_strlen:
	ldr	v1, sp, 2
	clr	v0
__strlen_loop:
	ldrl	v2, v1, 0
	seth	v2, 0
	eq	v2, 0
	b	__strlen_next
	rts
__strlen_next:
	add	v0, v0, 1
	add	v1, v1, 1
	b	__strlen_loop

_memset:
	ldr	v0, sp, 6
	mov	v1, v0
	ldr	v2, sp, 4
	ldr	v3, sp, 2
__memset_loop:
	eq	v3, 0
	b	__memset_body
	rts
__memset_body:
	strl	v2, v1, 0
	add	v1, v1, 1
	sub	v3, v3, 1
	b	__memset_loop

_memcpy:
	ldr	v1, sp, 6
	ldr	v2, sp, 4
	ldr	v3, sp, 2
__memcpy_loop:
	eq	v3, 0
	b	__memcpy_body
	ldr	v0, sp, 6
	rts
__memcpy_body:
	ldrl	v0, v2, 0
	strl	v0, v1, 0
	add	v1, v1, 1
	add	v2, v2, 1
	sub	v3, v3, 1
	b	__memcpy_loop

_memcmp:
	ldr	v1, sp, 6
	ldr	v2, sp, 4
	ldr	v3, sp, 2
	add	v3, v1, v3
	cc_push	v4
__memcmp_loop:
	eq	v1, v3
	b	__memcmp_body
	clr	v0
	cc_pop	v4
	rts
__memcmp_body:
	ldrl	v0, v1, 0
	seth	v0, 0
	ldrl	v4, v2, 0
	seth	v4, 0
	ne	v0, v4
	b	__memcmp_equal
	sub	v0, v0, v4
	cc_pop	v4
	rts
__memcmp_equal:
	add	v1, v1, 1
	add	v2, v2, 1
	b	__memcmp_loop

_strcpy:
	ldr	v1, sp, 4
	ldr	v2, sp, 2
__strcpy_loop:
	ldrl	v0, v2, 0
	seth	v0, 0
	strl	v0, v1, 0
	eq	v0, 0
	b	__strcpy_next
	ldr	v0, sp, 4
	rts
__strcpy_next:
	add	v1, v1, 1
	add	v2, v2, 1
	b	__strcpy_loop

_strcmp:
	ldr	v1, sp, 4
	ldr	v2, sp, 2
	cc_push	v4
__strcmp_loop:
	ldrl	v0, v1, 0
	seth	v0, 0
	ldrl	v4, v2, 0
	seth	v4, 0
	ne	v0, v4
	b	__strcmp_equal
	sub	v0, v0, v4
	cc_pop	v4
	rts
__strcmp_equal:
	eq	v0, 0
	b	__strcmp_next
	clr	v0
	cc_pop	v4
	rts
__strcmp_next:
	add	v1, v1, 1
	add	v2, v2, 1
	b	__strcmp_loop

_strchr:
	ldr	v1, sp, 4
	ldr	v2, sp, 2
	set	v3, $00ff
	and	v2, v2, v3
__strchr_loop:
	ldrl	v0, v1, 0
	seth	v0, 0
	ne	v0, v2
	b	__strchr_found
	eq	v0, 0
	b	__strchr_next
	clr	v0
	rts
__strchr_next:
	add	v1, v1, 1
	b	__strchr_loop
__strchr_found:
	mov	v0, v1
	rts

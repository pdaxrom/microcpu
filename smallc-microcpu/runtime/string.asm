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

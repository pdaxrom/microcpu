INITVAL	equ	$0

	setl	v1, INITVAL
	seth	v1, 0
	seth	v0, $ff
	setl	v0, 0
.1	strl	v1, v0, 0
	add	v1, v1, 1
	b	.1

	ds	$100-*

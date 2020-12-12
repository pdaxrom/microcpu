INITVAL	equ	$30
STEP	equ	$1

	seth	v0, $ff
	setl	v0, $ff

	seth	v1, 0
	setl	v1, INITVAL

	seth	v2, 0
	setl	v2, STEP

.1	strl	v1, v0, 0
;	add	v1, v1, 1
	add	v1, v1, v2
;;	strl	v2, v0, 0
	b	.1

	ds	$100-*

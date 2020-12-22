	include ../include/pseudo.inc
	include ../include/devmap.inc

	org	$100

begin:
	set	sp, $7fe

	set	v1, text
	seth	v0, 0
loop:
	ldrl	v0, v1, 0
	beq	loopexit, v0, 0
	bsr	printnum
	add	v1, v1, 1
	b	loop
loopexit:
	b	begin

printnum:
	push	v1
	push	v2
	set	v1, $e6e0
printnum1:
	ldrl	v2, v1, 0
	maskne	printnum1, v2, 2
printnum2:
	strl	v0, v1, 1
	pop	v2
	pop	v1
	rts

text:
	db	"Hello, World!", 10, 13, 0

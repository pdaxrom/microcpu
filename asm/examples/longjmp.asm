	include ../include/pseudo.inc
	include ../include/devmap.inc

	org	$2000

start	set	v0, text
	jsr	VEC_DISPTXT
	set	v1, 4
loop	set	v0, hello
	jsr	VEC_PUTSTR
	sub	v1, v1, 1
	bne	loop, v1, 0
	jmp	VEC_WARMUP

hello	db	10, 13, 'Hello, World!', 10, 13, 0

text	db	"Long jum"
	db	"p demo! "
	db	"        "
	db	"        "

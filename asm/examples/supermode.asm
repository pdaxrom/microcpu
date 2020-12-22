	include ../include/pseudo.inc
	include ../include/devmap.inc

	org	$100

	b	begin

isr	set	v0, tousr
	bsr	VEC_PUTSTR

	swu

begin	set	sp, $07fe

; set super vector
	set	v1, 2
	set	v2, $80B0
	str	v2, v1, 0

	set	v0, tosup
	bsr	VEC_PUTSTR

	sws

	set	v0, okay
	bsr	VEC_PUTSTR

stop	b	VEC_RESET

tosup	db	10, 13, "Switch to super mode", 10, 13, 0
tousr	db	10, 13, "Switch to user  mode", 10, 13, 0
okay	db	10, 13, "Hello from user mode", 10, 13, 0

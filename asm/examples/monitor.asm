	include ../include/pseudo.inc
	include ../include/devmap.inc

	org	$100

	b	main

isr	proc
	sub	sp, sp, 14
	push	v0
	push	v1
	push	v2
	push	v3

	set	v3, MMAP_ADDR
	getp	v0

	shr	v0, v0, 8
	setl	v1, %11111000
	and	v0, v0, v1

	seth	v2, 0
	ldrl	v2, v3, 2		; memory violation page
	beq	skip, v0, 0		; interrupt from page 0, it's not remapping
	beq	load_c, v0, v2		; load code page if mem violation and interrupt pages the same

skip	ldrl	v0, v3, 1
	bne	load_d, v0, v2

	set	v0, inter_i
	bsr	VEC_PUTSTR

;	set	v1, TIMER_ADDR
;	ldrl	v0, v1, 2	; reset timer interrupt flag
;	maskeq	next, v0, 1
;	set	v0, timer_i
;	bsr	VEC_PUTSTR

exit	pop	v3
	pop	v2
	pop	v1
	pop	v0
	add	sp, sp, 14
	swu

load_c	ldrl	v0, v3, 0
	shl	v0, v0, 8
	set	v1, 2048
	bsr	sram_save_page
	strl	v2, v3, 0
	shl	v0, v2, 8
	set	v1, 2048
	bsr	sram_load_page
	b	exit
load_d	getp	v1
	sub	v1, v1, 2
	setp	v1
	shl	v0, v0, 8
	set	v1, 2048
	bsr	sram_save_page
	strl	v2, v3, 1
	shl	v0, v2, 8
	set	v1, 2048
	bsr	sram_load_page
	b	exit

inter_i	db	'Interrupt', 0
codep_i	db	'Load code page', 0
datap_i	db	'Load data page', 0
timer_i	db	'Timer interrupt ', 10, 13, 0
sws_i	db	'SWS interrupt ', 10, 13, 0
	align	1
	endp

sram_save_page proc
	push	lr
;	push	v0
;	set	v0, text
;	bsr	VEC_PUTSTR
;	pop	v0
;	bsr	printhex
;	set	v0, nl
;	bsr	VEC_PUTSTR
	push	v2
	mov	v2, v1
	mov	v1, v0
	bsr	ram_write_mem
	pop	v2
	pop	lr
	rts
text	db	10, 13, 'save page ', 0
	align	1
	endp

sram_load_page proc
	push	lr
;	push	v0
;	set	v0, text
;	bsr	VEC_PUTSTR
;	pop	v0
;	bsr	printhex
;	set	v0, nl
;	bsr	VEC_PUTSTR
	push	v2
	mov	v2, v1
	mov	v1, v0
	bsr	ram_read_mem
	pop	v2
	pop	lr
	rts
text	db	10, 13, 'load page ', 0
	align	1
	endp

main	set	sp, $07fe

	set	v1, 2
	set	v2, $80B0
	str	v2, v1, 0

	set	v0, banner
	bsr	VEC_PUTSTR

	bsr	ram_init

	set	v0, sysiniv
	ldr	v1, v0, 0
	set	v2, $a55a
	beq	mainloop, v1, v2
	str	v2, v0, 0
	set	v0, $800
	set	v1, $F800
	setl	v2, 0
clrmem	strl	v2, v0, 0
	add	v0, v0, 1
	bne	clrmem, v0, v1

; main loop

mainloop proc
	set	v0, prompt
	bsr	VEC_PUTSTR
	set	v1, lastch
	bsr	gethex
	str	v0, v1, 2
	ldr	v0, v1, 0
	set	v2, '.'
	bne	action, v0, v2
	bsr	gethex
	str	v0, v1, 4
action	set	v0, nl
	bsr	VEC_PUTSTR
	ldr	v0, v1, 0
	setl	v2, 'X'
	beq	hexdump, v0, v2
	setl	v2, 'P'
	beq	chrdump, v0, v2
	setl	v2, 'G'
	beq	goaddr, v0, v2
	setl	v2, 'M'
	beq	setmem, v0, v2
	b	mainloop
	endp

setmem	proc
	ldr	v2, v1, 2

	set	v0, nl
	bsr	VEC_PUTSTR

loop	mov	v0, v2
	bsr	printhex
	setl	v0, ' '
	bsr	VEC_PUTCHAR
	bsr	gethex
	set	v1, lastch
	ldr	v1, v1, 0
	set	v3, $0d
	bne	exit, v1, v3
	strl	v0, v2, 0
	add	v2, v2, 1
	set	v0, nl
	bsr	VEC_PUTSTR
	b	loop
exit	b	mainloop
	endp

goaddr	proc
	ldr	v2, v1, 2
	mov	pc, v2
	endp

hexdump	proc
	ldr	v2, v1, 4
	ldr	v1, v1, 2
dump1	mov	v0, v1
	bsr	printhex
	setl	v0, ' '
	bsr	VEC_PUTCHAR
	set	v3, 16
dump2	ldrl	v0, v1, 0
	bsr	printhex8
	setl	v0, ' '
	bsr	VEC_PUTCHAR
	add	v1, v1, 1
	beq	dump3, v1, v2
	sub	v3, v3, 1
	bne	dump2, v3, 0
	set	v0, nl
	bsr	VEC_PUTSTR
	b	dump1
dump3	b	mainloop
	endp

chrdump	proc
	ldr	v2, v1, 4
	ldr	v1, v1, 2
	seth	v4, 0
dump1	mov	v0, v1
	bsr	printhex
	setl	v0, ' '
	bsr	VEC_PUTCHAR
	set	v3, 16
	seth	v0, 0
dump2	ldrl	v0, v1, 0
	setl	v4, $20
	bltu	dot, v0, v4
	setl	v4, $80
	ltu	v0, v4
dot	setl	v0, '.'
	bsr	VEC_PUTCHAR
	setl	v0, ' '
	bsr	VEC_PUTCHAR
	add	v1, v1, 1
	beq	dump3, v1, v2
	sub	v3, v3, 1
	bne	dump2, v3, 0
	set	v0, nl
	bsr	VEC_PUTSTR
	b	dump1
dump3	b	mainloop
	endp

printhex proc
	push	lr
	push	v0
	shr	v0, v0, 8
	bsr	printhex8
	pop	v0
	bsr	printhex8
	pop	lr
	rts
	endp

printhex8 proc
	push	lr
	push	v0
	push	v1
	set	v1, nums
	seth	v0, 0
	push	v0
	shr	v0, v0, 4
	add	v0, v1, v0
	ldrl	v0, v0, 0
	bsr	VEC_PUTCHAR
	pop	v0
	and	v0, v0, 15
	add	v0, v1, v0
	ldrl	v0, v0, 0
	bsr	VEC_PUTCHAR
	pop	v1
	pop	v0
	pop	lr
	rts
nums	db	'0123456789ABCDEF'
	endp

gethex	proc
	push	lr
	push	v1
	push	v2
	push	v3

	sub	v3, v3, v3
	seth	v0, 0
	set	v1, lastch
loop	bsr	VEC_GETCHAR
	bsr	VEC_PUTCHAR
	str	v0, v1, 0
	set	v2, '0'
	sub	v0, v0, v2
	bltu	okay, v0, 10
	sub	v0, v0, 7
	bltu	exit, v0, 10
	bgtu	exit, v0, 15
okay	shl	v3, v3, 4
	or	v3, v3, v0
	b	loop

exit	mov	v0, v3
	pop	v3
	pop	v2
	pop	v1
	pop	lr
	rts
	endp

	include	ramspi.inc

banner	db	10, 13, 'pdaXrom monitor', 0
prompt	db	10, 13, '>', 0
nl	db	10, 13, 0

sysiniv	dw	0

lastch	dw	0
saddr	dw	0
eaddr	dw	0

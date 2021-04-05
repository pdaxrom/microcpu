;
; BOOTROM for microcpu
; (c) sashz <sashz@pdaXrom.org>, 2020-2021
;

	include ../asm/include/pseudo.inc
	include ../asm/include/devmap.inc

	org	$0

	b	init
	b	isr		; reserved for external interrupt
	dw	0		; timer irq
	dw	0		; superuser irq
	b	begin
	b	flush_rampages
	b	getchar
	b	putchar
	b	printstr

init	set	sp, $07fe

	bsr	ram_init

; load initial mapped pages from sram
	set	v3, MMAP_ADDR

	setl	v2, $08
	strl	v2, v3, 0	; Init SRAM1 page
	shl	v0, v2, 8
	bsr	sram_load_page
	strl	v2, v3, 0	; reset dirty flag

	setl	v2, $10
	strl	v2, v3, 1	; Init SRAM2 page
	shl	v0, v2, 8
	bsr	sram_load_page
	strl	v2, v3, 1	; reset dirty flag
;

begin	set	sp, $07fe

	clr	v2
	set	v1, UART_ADDR
	seth	v0, 0
bootch1	ldrl	v0, v1, 0
	biteq	bootch2, v0, 1
	sub	v2, v2, 1
	beq	modchk, v2, 0
	b	bootch1
bootch2	ldrl	v0, v1, 1
	setl	v2, 'z'
	bne	modchk, v0, v2
	setl	v0, 'Z'
	bsr	putchar
	b	bootld

modchk	set	v1, $f000
modchk1	bsr	check_module
	set	v0, $800
	sub	v1, v1, v0
	bne	modchk1, v1, 0

bootld	set	sp, $07fe
	set	v0, banner
	bsr	printstr

	seth	v1, 0
mainloop bsr	getchar
	setl	v1, 'L'
	beq	cmd_load, v0, v1
	setl	v1, 'S'
	beq	cmd_save, v0, v1
	setl	v1, 'G'
	beq	cmd_go, v0, v1
	b	mainloop

cmd_load proc
	bsr	get_word
	mov	v1, v0
	bsr	get_word
	mov	v2, v0

	sub	sp, sp, 14
	mov	v3, sp
	add	v3, v3, 2
	seth	v4, 0

loop	setl	v4, 0

loop1	bsr	getchar
	strl	v0, v3, v4
	add	v4, v4, 1
	bne	loop1, v4, 14

	setl	v4, 0

loop2	ldrl	v0, v3, v4
	strl	v0, v1, 0
	add	v4, v4, 1
	add	v1, v1, 1
	beq	break, v1, v2
	bne	loop2, v4, 14
break	bsr	putchar		; echo to get sync transfer
	bne	loop, v1, v2
	add	sp, sp, 14
	bsr	flush_rampages
	b	bootld
	endp

cmd_save proc
	bsr	get_word
	mov	v1, v0
	bsr	get_word
	mov	v2, v0

loop	ldrl	v0, v1, 0
	bsr	putchar
	add	v1, v1, 1
	bne	loop, v1, v2
	b	bootld
	endp

cmd_go	proc
	bsr	get_word
	mov	pc, v0
	endp

get_word proc
	mov	v4, lr
	bsr	getchar
	mov	v3, v0
	bsr	getchar
	movh	v0, v3
	mov	pc, v4
	endp

printstr proc
	sub	sp, sp, 6
	str	lr, sp, 6
	str	v0, sp, 4
	str	v1, sp, 2
	mov	v1, v0
	seth	v0, 0
.1	ldrl	v0, v1, 0
	beq	.2, v0, 0
	bsr	putchar
	add	v1, v1, 1
	b	.1
.2	ldr	v1, sp, 2
	ldr	v0, sp, 4
	ldr	lr, sp, 6
	add	sp, sp, 6
	rts
	endp

putchar	proc
	sub	sp, sp, 2
	str	v1, sp, 2
	str	v2, sp, 0
	set	v1, UART_ADDR
.1	ldrl	v2, v1, 0
	biteq	.1, v2, 2
	strl	v0, v1, 1
	ldr	v2, sp, 0
	ldr	v1, sp, 2
	add	sp, sp, 2
	rts
	endp

getchar	proc
	str	v1, sp, 0
	set	v1, UART_ADDR
	seth	v0, 0
.1	ldrl	v0, v1, 0
	bitne	.1, v0, 1
	ldrl	v0, v1, 1
	ldr	v1, sp, 0
	rts
	endp

check_module proc
	sub	sp, sp, 4
	str	lr, sp, 4
	str	v1, sp, 2
	mov	v4, v1
	ldr	v1, v4, 0
	set	v2, $5aa5
	bne	exit, v1, v2
	mov	v0, v4
	ldr	v1, v4, 2
	bsr	calc_chksum
	inv	v0, v0
	bne	exit, v0, 0
	ldr	v0, v4, 4
	bsr	printstr
	set	v0, nl
	bsr	printstr
	set	lr, exit
	add	pc, v4, 8
exit	ldr	v1, sp, 2
	ldr	lr, sp, 4
	add	sp, sp, 4
	rts
	endp

calc_chksum proc
	sub	sp, sp, 4
	str	v2, sp, 4
	str	v3, sp, 2
	clr	v2
loop	ldr	v3, v0, 0
	add	v2, v2, v3
	add	v0, v0, 2
	bne	loop, v0, v1
	mov	v0, v2
	ldr	v3, sp, 2
	ldr	v2, sp, 4
	add	sp, sp, 4
	rts
	endp

isr	proc
	sub	sp, sp, 14
	str	lr, sp, 12
	str	v0, sp, 10
	str	v1, sp, 8
	str	v2, sp, 6
	str	v3, sp, 4
	str	v4, sp, 2

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
	and	v0, v0, v1
	bne	load_d, v0, v2

	set	v0, inter_i
	bsr	VEC_PUTSTR

;	set	v1, TIMER_ADDR
;	ldrl	v0, v1, 2	; reset timer interrupt flag
;	bitne	next, v0, 1
;	set	v0, timer_i
;	bsr	VEC_PUTSTR

exit	ldr	v4, sp, 2
	ldr	v3, sp, 4
	ldr	v2, sp, 6
	ldr	v1, sp, 8
	ldr	v0, sp, 10
	ldr	lr, sp, 12
	add	sp, sp, 14
	swu

load_c	ldrl	v0, v3, 0
	bitne	load_c1, v0, 1	; no dirty flag, load only
	shr	v0, v0, 1
	shl	v0, v0, 9
	bsr	sram_save_page
load_c1	strl	v2, v3, 0
	shl	v0, v2, 8
	bsr	sram_load_page
	strl	v2, v3, 0	; reset dirty page flag after memory load
	b	exit

load_d	getp	v1
	sub	v1, v1, 2
	setp	v1
	ldrl	v0, v3, 1
	bitne	load_d1, v0, 1	; no dirty flag, load only
	shr	v0, v0, 1
	shl	v0, v0, 9
	bsr	sram_save_page
load_d1	strl	v2, v3, 1
	shl	v0, v2, 8
	bsr	sram_load_page
	strl	v2, v3, 1	; reset dirty page flag after memory load
	b	exit

inter_i	db	'Interrupt', 0
	align	1
	endp

flush_rampages proc
	sub	sp, sp, 8
	str	lr, sp, 8
	str	v3, sp, 6
	str	v2, sp, 4
	str	v0, sp, 2
	set	v3, MMAP_ADDR

	ldrl	v2, v3, 0
	shr	v0, v2, 1
	shl	v0, v0, 9
	bsr	sram_save_page
	strl	v2, v3, 0	; reset dirty page flag

	ldrl	v2, v3, 1
	shr	v0, v2, 1
	shl	v0, v0, 9
	bsr	sram_save_page
	strl	v2, v3, 1	; reset dirty page flag

	ldr	v0, sp, 2
	ldr	v2, sp, 4
	ldr	v3, sp, 6
	ldr	lr, sp, 8
	add	sp, sp, 8
	rts
	endp

sram_save_page proc
	sub	sp, sp, 4
	str	lr, sp, 4
	str	v2, sp, 2
	mov	v1, v0
	set	v2, 2048
	bsr	ram_write_mem
	ldr	v2, sp, 2
	ldr	lr, sp, 4
	add	sp, sp, 4
	rts
	endp

sram_load_page proc
	sub	sp, sp, 4
	str	lr, sp, 4
	str	v2, sp, 2
	mov	v1, v0
	set	v2, 2048
	bsr	ram_read_mem
	ldr	v2, sp, 2
	ldr	lr, sp, 4
	add	sp, sp, 4
	rts
	endp

banner	db	"Z/pdaXrom"
nl	db	10, 13, 0
	align	1

	include	framspi.inc

	ds	$800-*

;
; SPI RAM
;
; GPIO 8  - SISIO0
; GPIO 9  - SOSIO1
; GPIO 10 - SCK
; GPIO 11 - CS
;

	include ../include/pseudo.inc
	include ../include/devmap.inc

PIN_SISIO0	equ	1
PIN_SOSIO1	equ	2
PIN_SCK		equ	4
PIN_CS		equ	8

CMD_WREN	equ	$06
CMD_WRDI	equ	$04
CMD_RDSR	equ	$05
CMD_WRSR	equ	$01
CMD_READ	equ	$03
CMD_WRITE	equ	$02
CMD_FSTRD	equ	$0b
CMD_RDID	equ	$9f
CMD_SLEEP	equ	$b9

	org	$800

begin	set	sp, $07fe

;	bsr	spi_mode

	set	v0, t_1
	jsr	VEC_PUTSTR

	bsr	read_id
	bsr	printhex8

	mov	v0, v1
	bsr	printhex

	set	v0, nl
	jsr	VEC_PUTSTR

;	setl	v0, CMD_WREN
;	bsr	write_cmd

	bsr	read_mode
	bsr	printhex8

	set	v0, nl
	jsr	VEC_PUTSTR

stop	jmp	VEC_RESET

dump	proc
	push	lr
	push	v0
	bsr	printhex8
	set	v0, nl
	jsr	VEC_PUTSTR
	pop	v0
	pop	lr
	rts
	endp

t_1	db	10, 13, 'Init', 10, 13, 0
t_5	db	10, 13, 'Stop', 0
nl	db	10, 13, 0

	align	2


write_cmd proc
	push	lr
	push	v1
	set	v1, GPIO_ADDR
	bsr	sram_cs_low
	bsr	writespi
	bsr	sram_cs_high
	pop	v1
	pop	lr
	rts
	endp

write_mode proc
	push	lr
	push	v1
	set	v1, GPIO_ADDR
	bsr	sram_cs_low
	push	v0
	setl	v0, CMD_WRSR
	bsr	writespi
	pop	v0
	bsr	writespi
	bsr	sram_cs_high
	pop	v1
	pop	lr
	rts
	endp

read_mode proc
	push	lr
	push	v1
	set	v1, GPIO_ADDR
	bsr	sram_cs_low
	setl	v0, CMD_RDSR
	bsr	writespi
	bsr	readspi
	seth	v0, 0
	bsr	sram_cs_high
	pop	v1
	pop	lr
	rts
	endp

read_id proc
	push	lr
	push	v2
	set	v1, GPIO_ADDR
	bsr	sram_cs_low
	setl	v0, CMD_RDID
	bsr	writespi
	bsr	readspi
	movh	v2, v0
	bsr	readspi
	movl	v2, v0
	bsr	readspi
	seth	v0, 0
	bsr	sram_cs_high
	mov	v1, v2
	pop	v2
	pop	lr
	rts
	endp

writespi proc
	push	lr
	push	v0
	push	v2
	push	v3
	push	v4

	set	v2, 8

loop	set	v3, $80
	ldrl	v4, v1, 0
	or	v4, v4, PIN_SISIO0
	mne	v0, v3
	xor	v4, v4, PIN_SISIO0
	strl	v4, v1, 0

	setl	v3, PIN_SCK
	or	v4, v4, v3
	strl	v4, v1, 0
	xor	v4, v4, v3
	strl	v4, v1, 0

	shl	v0, v0, 1
	sub	v2, v2, 1
	bne	loop, v2, 0

	pop	v4
	pop	v3
	pop	v2
	pop	v0
	pop	lr
	rts
	endp

readspi	proc
	push	lr
	push	v2
	push	v3
	push	v4

	set	v2, 8

loop	shl	v0, v0, 1
	ldrl	v4, v1, 0
	meq	v4, PIN_SOSIO1
	or	v0, v0, 1

	setl	v3, PIN_SCK
	or	v4, v4, v3
	strl	v4, v1, 0
	xor	v4, v4, v3
	strl	v4, v1, 0

	sub	v2, v2, 1
	bne	loop, v2, 0

	pop	v4
	pop	v3
	pop	v2
	pop	lr
	rts
	endp

sram_cs_low proc
	push	v3
	push	v4
	ldrl	v4, v1, 0
	setl	v3, $FF^PIN_CS
	and	v4, v4, v3
	strl	v4, v1, 0
	pop	v4
	pop	v3
	rts
	endp

sram_cs_high proc
	push	v3
	push	v4
	ldrl	v4, v1, 0
	setl	v3, PIN_CS
	or	v4, v4, v3
	strl	v4, v1, 0
	pop	v4
	pop	v3
	rts
	endp

spi_mode proc
	push	v0
	push	v1
	push	v2
	set	v1, GPIO_ADDR
	ldrl	v0, v1, 0
	setl	v2, $ff^(PIN_SCK | PIN_SISIO0 | PIN_SOSIO1)
	and	v0, v0, v2
	setl	v2, PIN_CS
	or	v0, v0, v2
	strl	v0, v1, 0

	ldrl	v0, v1, 2
	setl	v2, $ff^PIN_SOSIO1
	and	v0, v0, v2
	setl	v2, (PIN_SISIO0 | PIN_SCK | PIN_CS)
	or	v0, v0, v2
	strl	v0, v1, 2
	pop	v2
	pop	v1
	pop	v0
	rts
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
	jsr	VEC_PUTCHAR
	pop	v0
	and	v0, v0, 15
	add	v0, v1, v0
	ldrl	v0, v0, 0
	jsr	VEC_PUTCHAR
	pop	v1
	pop	v0
	pop	lr
	rts
nums	db	'0123456789ABCDEF'
	endp

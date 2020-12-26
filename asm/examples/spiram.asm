;
; SPI RAM
;
; GPIO 8  - SISIO0
; GPIO 9  - SOSIO1
; GPIO 10 - SIO3
; GPIO 11 - SIO3
; GPIO 12 - SCK
; GPIO 13 - CS
;

	include ../include/pseudo.inc
	include ../include/devmap.inc

PIN_SISIO0	equ	1
PIN_SOSIO1	equ	2
PIN_SIO2	equ	4
PIN_HOLDSIO3	equ	8
PIN_SCK		equ	16
PIN_CS		equ	32

CMD_READ	equ	$03
CMD_WRITE	equ	$02
CMD_EDIO	equ	$3b
CMD_EQIO	equ	$38
CMD_RSTIO	equ	$ff
CMD_RDMR	equ	$05
CMD_WRMR	equ	$01

	org	$100

begin	set	sp, $07fe

	bsr	spi_mode

	set	v0, t_1
	bsr	VEC_PUTSTR

	bsr	read_mode
	bsr	printhex8

	set	v0, $80
	bsr	write_mode

	bsr	read_mode
	bsr	printhex8

	set	v0, $40
	bsr	write_mode

	bsr	read_mode
	bsr	printhex8
;

	set	v0, nl
	bsr	VEC_PUTSTR

	setl	v0, CMD_EQIO
	bsr	write_cmd

;	setl	v0, CMD_RSTIO
;	bsr	sqi_write_cmd

	bsr	sqi_read_mode
	bsr	printhex8

	set	v0, $80
	bsr	sqi_write_mode

	bsr	sqi_read_mode
	bsr	printhex8

	setl	v0, CMD_RSTIO
	bsr	sqi_write_cmd

	bsr	spi_mode

	bsr	read_mode
	bsr	printhex8
;

	set	v0, t_5
	bsr	VEC_PUTSTR

stop	b	VEC_RESET

dump	proc
	push	lr
	push	v0
	bsr	printhex8
	set	v0, nl
	bsr	VEC_PUTSTR
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
	setl	v0, CMD_WRMR
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
	setl	v0, CMD_RDMR
	bsr	writespi
	bsr	readspi
	seth	v0, 0
	bsr	sram_cs_high
	pop	v1
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
	setl	v2, (PIN_CS | PIN_HOLDSIO3)
	or	v0, v0, v2
	strl	v0, v1, 0

	ldrl	v0, v1, 2
	setl	v2, $ff^PIN_SOSIO1
	and	v0, v0, v2
	setl	v2, (PIN_SISIO0 | PIN_SIO2 | PIN_HOLDSIO3 | PIN_SCK | PIN_CS)
	or	v0, v0, v2
	strl	v0, v1, 2
	pop	v2
	pop	v1
	pop	v0
	rts
	endp

;
; SQI mode functions
;

sqi_write_cmd proc
	push	lr
	push	v1
	set	v1, GPIO_ADDR
	bsr	sqi_mode_write
	bsr	sram_cs_low
	bsr	writesqi
	bsr	sram_cs_high
	pop	v1
	pop	lr
	rts
	endp


sqi_write_mode proc
	push	lr
	push	v1
	set	v1, GPIO_ADDR
	bsr	sqi_mode_write
	bsr	sram_cs_low
	push	v0
	setl	v0, CMD_WRMR
	bsr	writesqi
	pop	v0
	bsr	writesqi
	bsr	sram_cs_high
	pop	v1
	pop	lr
	rts
	endp

sqi_read_mode proc
	push	lr
	push	v1
	set	v1, GPIO_ADDR
	bsr	sqi_mode_write
	bsr	sram_cs_low
	setl	v0, CMD_RDMR
	bsr	writesqi
	bsr	sqi_mode_read
	bsr	readsqi
	seth	v0, 0
	bsr	sram_cs_high
	pop	v1
	pop	lr
	rts
	endp

sqi_mode_write proc
	push	v0
	push	v2
	ldr	v0, v1, 2
	setl	v2, (PIN_SISIO0 | PIN_SOSIO1 | PIN_SIO2 | PIN_HOLDSIO3)
	or	v0, v0, v2
	strl	v0, v1, 2
	pop	v2
	pop	v0
	rts
	endp

sqi_mode_read proc
	push	v0
	push	v2
	ldr	v0, v1, 2
	setl	v2, $ff^(PIN_SISIO0 | PIN_SOSIO1 | PIN_SIO2 | PIN_HOLDSIO3)
	and	v0, v0, v2
	strl	v0, v1, 2
	pop	v2
	pop	v0
	rts
	endp

writesqi proc
	push	lr
	push	v0
	push	v2
	push	v3
	push	v4

	set	v2, 2
	movh	v0, v0

loop	ldrl	v4, v1, 0
	setl	v3, $ff^(PIN_SISIO0 | PIN_SOSIO1 | PIN_SIO2 | PIN_HOLDSIO3)
	and	v4, v4, v3
	shr	v0, v0, 4
	inv	v3, v3
	and	v3, v3, v0
	or	v4, v4, v3
	strl	v4, v1, 0

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
	pop	v0
	pop	lr
	rts
	endp

readsqi	proc
	push	lr
	push	v2
	push	v3
	push	v4

	set	v2, 2

loop	shl	v0, v0, 4
	ldrl	v4, v1, 0
	setl	v3, (PIN_SISIO0 | PIN_SOSIO1 | PIN_SIO2 | PIN_HOLDSIO3)
	and	v3, v3, v4
	or	v0, v0, v3

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

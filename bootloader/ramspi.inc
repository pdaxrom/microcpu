;
; SPI RAM
;
; GPIO 8  - SISIO0
; GPIO 9  - SOSIO1
; GPIO 10 - SCK
; GPIO 11 - CS
;

PIN_SISIO0	equ	1
PIN_SOSIO1	equ	2
PIN_SCK		equ	4
PIN_CS		equ	8

CMD_READ	equ	$03
CMD_WRITE	equ	$02
CMD_EDIO	equ	$3b
CMD_EQIO	equ	$38
CMD_RSTIO	equ	$ff
CMD_RDMR	equ	$05
CMD_WRMR	equ	$01

ram_init proc
	global	ram_write_cmd, ram_write_mode, ram_read_mode, ram_set_gpio, ram_write_mem, ram_read_mem
	push	lr
	bsr	ram_set_gpio
	set	v0, $40
	bsr	ram_write_mode
	pop	lr
	rts

ram_write_mem
	sub	sp, sp, 10
	str	lr, sp, 10
	str	v0, sp, 8
	str	v1, sp, 6
	str	v2, sp, 4
	str	v3, sp, 2
	set	v1, GPIO_ADDR
	bsr	sram_cs_low
	setl	v0, CMD_WRITE
	bsr	writespi
	setl	v0, 0
	bsr	writespi
	ldrl	v0, sp, 9
	bsr	writespi
	ldrl	v0, sp, 8
	bsr	writespi

	ldr	v2, sp, 6
	ldr	v3, sp, 4

ram_write_mem_loop
	ldrl	v0, v2, 0
	bsr	writespi
	add	v2, v2, 1
	sub	v3, v3, 1
	bne	ram_write_mem_loop, v3, 0

	bsr	sram_cs_high
	ldr	v3, sp, 2
	ldr	v2, sp, 4
	ldr	v1, sp, 6
	ldr	v0, sp, 8
	ldr	lr, sp, 10
	add	sp, sp, 10
	rts

ram_read_mem
	sub	sp, sp, 10
	str	lr, sp, 10
	str	v0, sp, 8
	str	v1, sp, 6
	str	v2, sp, 4
	str	v3, sp, 2
	set	v1, GPIO_ADDR
	bsr	sram_cs_low
	setl	v0, CMD_READ
	bsr	writespi
	setl	v0, 0
	bsr	writespi
	ldrl	v0, sp, 9
	bsr	writespi
	ldrl	v0, sp, 8
	bsr	writespi

	ldr	v2, sp, 6
	ldr	v3, sp, 4

ram_read_mem_loop
	bsr	readspi
	strl	v0, v2, 0
	add	v2, v2, 1
	sub	v3, v3, 1
	bne	ram_read_mem_loop, v3, 0

	bsr	sram_cs_high
	ldr	v3, sp, 2
	ldr	v2, sp, 4
	ldr	v1, sp, 6
	ldr	v0, sp, 8
	ldr	lr, sp, 10
	add	sp, sp, 10
	rts

ram_write_cmd
	sub	sp, sp, 4
	str	lr, sp, 4
	str	v1, sp, 2
	set	v1, GPIO_ADDR
	bsr	sram_cs_low
	bsr	writespi
	bsr	sram_cs_high
	ldr	v1, sp, 2
	ldr	lr, sp, 4
	add	sp, sp, 4
	rts

ram_write_mode
	sub	sp, sp, 6
	str	lr, sp, 6
	str	v1, sp, 4
	str	v0, sp, 2
	set	v1, GPIO_ADDR
	bsr	sram_cs_low
	setl	v0, CMD_WRMR
	bsr	writespi
	ldr	v0, sp, 2
	bsr	writespi
	bsr	sram_cs_high
	ldr	v1, sp, 4
	ldr	lr, sp, 6
	add	sp, sp, 6
	rts

ram_read_mode
	sub	sp, sp, 4
	str	lr, sp, 4
	str	v1, sp, 2
	set	v1, GPIO_ADDR
	bsr	sram_cs_low
	setl	v0, CMD_RDMR
	bsr	writespi
	bsr	readspi
	seth	v0, 0
	bsr	sram_cs_high
	ldr	v1, sp, 2
	ldr	lr, sp, 4
	add	sp, sp, 4
	rts

writespi
	sub	sp, sp, 10
	str	lr, sp, 10
	str	v0, sp, 8
	str	v2, sp, 6
	str	v3, sp, 4
	str	v4, sp, 2

	set	v2, 8
	set	v3, $80
wloop	ldrl	v4, v1, 0
	or	v4, v4, PIN_SISIO0
	bts	v0, v3
	xor	v4, v4, PIN_SISIO0
	strl	v4, v1, 0

	or	v4, v4, PIN_SCK
	strl	v4, v1, 0
	xor	v4, v4, PIN_SCK
	strl	v4, v1, 0

	shl	v0, v0, 1
	sub	v2, v2, 1
	bne	wloop, v2, 0

	ldr	v4, sp, 2
	ldr	v3, sp, 4
	ldr	v2, sp, 6
	ldr	v0, sp, 8
	ldr	lr, sp, 10
	add	sp, sp, 10
	rts

readspi
	sub	sp, sp, 8
	str	lr, sp, 8
	str	v2, sp, 6
	str	v3, sp, 4
	str	v4, sp, 2

	set	v2, 8
rloop	shl	v0, v0, 1
	ldrl	v4, v1, 0
	btc	v4, PIN_SOSIO1
	or	v0, v0, 1

	or	v4, v4, PIN_SCK
	strl	v4, v1, 0
	xor	v4, v4, PIN_SCK
	strl	v4, v1, 0

	sub	v2, v2, 1
	bne	rloop, v2, 0

	ldr	v4, sp, 2
	ldr	v3, sp, 4
	ldr	v2, sp, 6
	ldr	lr, sp, 8
	add	sp, sp, 8
	rts

sram_cs_low
	sub	sp, sp, 4
	str	v3, sp, 4
	str	v4, sp, 2
	ldrl	v4, v1, 0
	setl	v3, $FF^PIN_CS
	and	v4, v4, v3
	strl	v4, v1, 0
	ldr	v4, sp, 2
	ldr	v3, sp, 4
	add	sp, sp, 4
	rts

sram_cs_high
	str	v4, sp, 0
	ldrl	v4, v1, 0
	or	v4, v4, PIN_CS
	strl	v4, v1, 0
	ldr	v4, sp, 0
	rts

ram_set_gpio
;	sub	sp, sp, 6
;	str	v0, sp, 6
;	str	v1, sp, 4
;	str	v2, sp, 2
	set	v1, GPIO_ADDR
	ldrl	v0, v1, 0
	setl	v2, $ff^(PIN_SCK | PIN_SISIO0 | PIN_SOSIO1)
	and	v0, v0, v2
	or	v0, v0, PIN_CS
	strl	v0, v1, 0
;	ldr	v2, sp, 2
;	ldr	v1, sp, 4
;	ldr	v0, sp, 6
;	add	sp, sp, 6
	rts
	endp

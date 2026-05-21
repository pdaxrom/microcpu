;
; hc1200-microcomp virtual memory / FRAM smoke test.
; Build/run through the bootloader: make -C microemu run-boot-fram-vm
;
; The bootloader maps page $08 as the code window and uses page $10 as the
; data window. Accesses to other pages should fault into the bootloader ISR,
; which saves dirty mapped pages to SPI FRAM and loads the requested page back.
; The VM pass covers normal virtual pages $1000..$f000; page $f800 contains
; the MMIO window at $ffe0..$ffff. The final pass overwrites and verifies every
; byte of both 64 KiB FRAM banks through direct SPI, covering the full 128 KiB
; device.
;

include ../../asm/include/pseudo.inc
include ../../asm/include/devmap.inc

VM_START	equ	$1000
VM_LIMIT	equ	$f800
VM_STEP		equ	$0800
VM_XOR		equ	$5a5a
CODE_PAGE	equ	$2000
PIN_MOSI	equ	1
PIN_MISO	equ	2
PIN_SCK		equ	4
PIN_CS		equ	8
CMD_WREN	equ	$06
CMD_READ	equ	$03
CMD_WRITE	equ	$02

org $0800

	set	sp, $07fe

	set	v1, VM_START
	set	v2, VM_STEP
	set	v3, VM_XOR
	set	v4, VM_LIMIT

vm_write_loop:
	mov	v0, v1
	xor	v0, v0, v3
	str	v0, v1, 0
	inv	v0, v0
	str	v0, v1, 2
	add	v1, v1, v2
	bne	vm_write_loop, v1, v4

	set	v1, VM_START

vm_read_loop:
	ldr	v0, v1, 0
	mov	v4, v1
	xor	v4, v4, v3
	bne	fail_vm_page, v0, v4
	ldr	v0, v1, 2
	inv	v4, v4
	bne	fail_vm_page, v0, v4
	set	v4, VM_LIMIT
	add	v1, v1, v2
	bne	vm_read_loop, v1, v4

	set	v1, CODE_PAGE
	set	v0, $de47	; setl v4, $de
	str	v0, v1, 0
	set	v0, $c057	; seth v4, $c0
	str	v0, v1, 2
	set	v0, $4080	; mov pc, lr
	str	v0, v1, 4

	jsr	CODE_PAGE
	set	v0, $c0de
	bne	fail_code_page, v4, v0

	bsr	full_fram_check

	set	v0, ok_message
	jsr	VEC_PUTSTR
	b	*

fail_vm_page:
	set	v0, err_vm_page
	b	fail
fail_code_page:
	set	v0, err_code_page

fail:
	jsr	VEC_PUTSTR
	setl	v0, 1
	seth	v0, 0
	mov	pc, v0

ok_message:
	db	"FRAM VM OK", 10, 13, 0
err_vm_page:
	db	"FRAM VM ERR PAGE", 10, 13, 0
err_code_page:
	db	"FRAM VM ERR CODE", 10, 13, 0
err_full_fram:
	db	"FRAM VM ERR FULL", 10, 13, 0

	align	1

full_fram_check proc
	push	lr
	setl	v2, 0
	seth	v2, 0
	bsr	fram_write_bank
	setl	v2, 1
	seth	v2, 0
	bsr	fram_write_bank
	setl	v2, 0
	seth	v2, 0
	bsr	fram_read_bank
	bne	full_fram_fail, v0, 0
	setl	v2, 1
	seth	v2, 0
	bsr	fram_read_bank
	bne	full_fram_fail, v0, 0
	pop	lr
	rts

full_fram_fail:
	pop	lr
	set	v0, err_full_fram
	b	fail
	endp

fram_write_bank proc
	push	lr
	setl	v0, CMD_WREN
	bsr	fram_write_cmd
	set	v1, GPIO_ADDR
	bsr	fram_cs_low
	setl	v0, CMD_WRITE
	bsr	fram_write_spi
	mov	v0, v2
	bsr	fram_write_spi
	setl	v0, 0
	bsr	fram_write_spi
	setl	v0, 0
	bsr	fram_write_spi

	setl	v4, 0
	seth	v4, 0
	eq	v2, 0
	setl	v4, $5a
	set	v3, 0

fram_write_bank_loop:
	mov	v0, v3
	seth	v0, 0
	xor	v0, v0, v4
	bsr	fram_write_spi
	add	v3, v3, 1
	bne	fram_write_bank_loop, v3, 0

	bsr	fram_cs_high
	pop	lr
	rts
	endp

fram_read_bank proc
	push	lr
	set	v1, GPIO_ADDR
	bsr	fram_cs_low
	setl	v0, CMD_READ
	bsr	fram_write_spi
	mov	v0, v2
	bsr	fram_write_spi
	setl	v0, 0
	bsr	fram_write_spi
	setl	v0, 0
	bsr	fram_write_spi

	setl	v4, 0
	seth	v4, 0
	eq	v2, 0
	setl	v4, $5a
	set	v3, 0

fram_read_bank_loop:
	bsr	fram_read_spi
	mov	v2, v3
	seth	v2, 0
	xor	v2, v2, v4
	bne	fram_read_bank_fail, v0, v2
	add	v3, v3, 1
	bne	fram_read_bank_loop, v3, 0
	setl	v0, 0
	seth	v0, 0
	b	fram_read_bank_done

fram_read_bank_fail:
	setl	v0, 1
	seth	v0, 0

fram_read_bank_done:
	bsr	fram_cs_high
	pop	lr
	rts
	endp

fram_write_cmd proc
	push	lr
	push	v1
	set	v1, GPIO_ADDR
	bsr	fram_cs_low
	bsr	fram_write_spi
	bsr	fram_cs_high
	pop	v1
	pop	lr
	rts
	endp

fram_write_spi proc
	push	lr
	push	v0
	push	v2
	push	v3
	push	v4

	set	v2, 8
	set	v3, $80

fram_write_spi_loop:
	ldrl	v4, v1, 0
	or	v4, v4, PIN_MOSI
	bts	v0, v3
	xor	v4, v4, PIN_MOSI
	strl	v4, v1, 0

	or	v4, v4, PIN_SCK
	strl	v4, v1, 0
	xor	v4, v4, PIN_SCK
	strl	v4, v1, 0

	shl	v0, v0, 1
	sub	v2, v2, 1
	bne	fram_write_spi_loop, v2, 0

	pop	v4
	pop	v3
	pop	v2
	pop	v0
	pop	lr
	rts
	endp

fram_read_spi proc
	push	lr
	push	v2
	push	v3
	push	v4

	set	v0, 0
	set	v2, 8

fram_read_spi_loop:
	shl	v0, v0, 1
	ldrl	v4, v1, 0
	btc	v4, PIN_MISO
	or	v0, v0, 1

	or	v4, v4, PIN_SCK
	strl	v4, v1, 0
	xor	v4, v4, PIN_SCK
	strl	v4, v1, 0

	sub	v2, v2, 1
	bne	fram_read_spi_loop, v2, 0

	pop	v4
	pop	v3
	pop	v2
	pop	lr
	rts
	endp

fram_cs_low proc
	push	v3
	push	v4
	ldrl	v4, v1, 0
	setl	v3, $ff^PIN_CS
	and	v4, v4, v3
	strl	v4, v1, 0
	pop	v4
	pop	v3
	rts
	endp

fram_cs_high proc
	push	v4
	ldrl	v4, v1, 0
	or	v4, v4, PIN_CS
	strl	v4, v1, 0
	pop	v4
	rts
	endp

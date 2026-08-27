include ../../asm/include/pseudo.inc

org $0000

	; All extended context words must reset to zero.
	set v2, 16
	set v4, 32
context_clear_check
	ggetr v1, v2
	bne failed, v1, 0
	inc v2
	bne context_clear_check, v2, v4

	; Dynamic high indexes must not alias guest registers or control ports.
	set v2, 16
	set v3, $5a5b
context_write_check
	gsetr v3, v2
	ggetr v1, v2
	bne failed, v1, v3
	inc v2
	bne context_write_check, v2, v4
	gget v1, 31
	bne failed, v1, v3
	gget v1, 16
	bne failed, v1, v3

	set v0, $1234
	gset v0, 7
	; Immediate access uses the same five-bit context index as GGETR/GSETR.
	gset v0, 23
	set v2, 23
	ggetr v1, v2
	bne failed, v1, v0
	gget v1, 7
	set v2, $2000
	str v1, v2, 0
	ldr v3, v2, 0
	bne failed, v3, v1

	; The synchronous register read port also supplies GSET/store operands.
	; Exercise byte writes without losing the untouched destination byte.
	set v0, $abcd
	movl v0, v1
	set v4, $ab34
	bne failed, v0, v4
	movh v0, v1
	set v4, $3434
	bne failed, v0, v4
	setl v0, $56
	seth v0, $78
	set v4, $7856
	bne failed, v0, v4
	gset v0, 29
	gget v4, 29
	bne failed, v0, v4

	; Register-offset address addition, byte load merge and a long SPI wait.
	set v2, $20f0
	set v4, $10
	str v0, v2, v4
	set v2, $2100
	set v4, $ab
	strl v4, v2, 1
	set v0, $c500
	ldrl v0, v2, 1
	set v4, $c5ab
	bne failed, v0, v4
	ldr v0, v2, 0
	set v4, $ab56
	bne failed, v0, v4

	; Load-PC transactions must preserve the same instruction and next-PC
	; byte merge for the entire memory wait, without duplicate mem_* latches.
	set v2, $2200
	set v1, word_jump_target
	str v1, v2, 0
	ldr pc, v2, 0
	b failed

	align $0100
word_jump_target
	set v1, byte_jump_target
	strl v1, v2, 0
	ldrl pc, v2, 0
	b failed
byte_jump_target
	set v3, $1234
	gset v3, 0
	b *

failed
	set v0, $ffff
	gset v0, 10
	gset v0, 0
	b *

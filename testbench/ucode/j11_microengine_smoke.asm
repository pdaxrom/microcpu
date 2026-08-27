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
	gset v3, 0
	b *

failed
	set v0, $ffff
	gset v0, 10
	gset v0, 0
	b *

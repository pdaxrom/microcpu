include ../../asm/include/pseudo.inc

org $0000

	set v0, $1234
	gset v0, 7
	gget v1, 7
	set v2, $2000
	str v1, v2, 0
	ldr v3, v2, 0
	gset v3, 0
	b *

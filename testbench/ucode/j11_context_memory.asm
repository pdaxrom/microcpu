include ../../asm/include/pseudo.inc

; Native RISC memory test, assembled just like production microcode.
; J11_CODE_WORDS is supplied by make; the final instruction is deliberately
; adjacent to the writable context, even in the last physical EBR bank.
org $0000

	set v2, 0
	set v4, 64
clear_check
	ggetr v1, v2
	bne failed, v1, 0
	inc v2
	bne clear_check, v2, v4

	set sp, $0101
	set v3, 1
pattern_pass
	set v2, 0
	mov v0, v3
write_words
	; These three indexes are native service ports, not ordinary RAM.
	beq next_write, v2, 10
	beq next_write, v2, 11
	beq next_write, v2, 15
	gsetr v0, v2
next_write
	add v0, v0, sp
	inc v2
	bne write_words, v2, v4
	set v2, 0
	mov v0, v3
read_words
	beq next_read, v2, 10
	beq next_read, v2, 11
	beq next_read, v2, 15
	ggetr v1, v2
	bne failed, v1, v0
next_read
	add v0, v0, sp
	inc v2
	bne read_words, v2, v4
	add v3, v3, v3
	bne pattern_pass, v3, 0

	; All high index bits are ignored, and A may also be the destination.
	set v0, $a55a
	set v2, $ffff
	gsetr v0, v2
	set v2, 63
	ggetr v2, v2
	bne failed, v2, v0
	set v2, $ffff
	ggetr v1, v2
	bne failed, v1, v0

	; Immediate accesses and native PC-source/PC-destination semantics.
pc_source
	gset pc, 30
	set v0, pc_source+1
	gget v1, 30
	bne failed, v1, v0
	set v0, immediate_target
	gset v0, 29
	gget pc, 29
	b failed
immediate_target
	set v0, success
	gset v0, 31
	set v2, 31
	set v1, last_code_word
	mov pc, v1
	b failed
success
	set v0, 2
	gset v0, 10
	b *
failed
	set v0, $ffff
	gset v0, 10
	b *

	ds (J11_CODE_WORDS-1)*2-*
last_code_word
	ggetr pc, v2

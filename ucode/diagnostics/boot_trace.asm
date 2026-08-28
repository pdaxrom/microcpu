; J11_BOOT_TRACE + J11_DISABLE_FIS only. Same CPU/board/native services.
; Trace records (all words HEX):
; TAG CMD LBAhi LBAlo OFF CS1 WC BA ER SP PC PS IR CAUSE V0 V1
; C=command response (V0=R1); R=read begins; V=CRC verified (V0=V1=CRC);
; D=RH command finished; G=guest snapshot; E=transport error; S=boot stopped;
; X=CRC mismatch (V0=received,V1=computed); K/M=cache/DMA mismatch
; (V0=expected,V1=readback; OFF=cache byte offset, BA=guest byte address).
;
; Only call at instruction boundaries / inside RH service / fatal stops.
; Context 12/13/18/39 is dead there: saved V0/V1/hex LR/trace LR.
; 61=last trace tick, 62[7:0]=CMD, 62[15]=suppress progress after guest TX.
; Never change guest registers, CSRs, PSW, flags or RX. V0/V1/V3/V4 preserved;
; V2/SP/native flags volatile. SP returns F008. UART is drained before return
; so a following guest XBUF write cannot collide with our final LF.

macro boot_trace_out
	ldi8 v2, #1
	call boot_trace_putc
endm
macro boot_trace_word
	boot_trace_out ' '
	gget v2, #1
	call boot_trace_hex
endm

boot_trace_banner
	gset lr, 39
	set sp, $f00c
	clr v2
	str v2, sp, 0
	set sp, $f006
	ldi8 v2, 1
	str v2, sp, 0            ; UART reset, no BREAK/loopback; no FRAM or SD I/O
	boot_trace_out 13
	boot_trace_out 10
	boot_trace_out 'J'
	boot_trace_out '1'
	boot_trace_out '1'
	boot_trace_out ' '
	boot_trace_out 'T'
	boot_trace_out 'R'
	boot_trace_out 'A'
	boot_trace_out 'C'
	boot_trace_out 'E'
	boot_trace_out ' '
	boot_trace_out 'N'
	boot_trace_out 'O'
	boot_trace_out 'F'
	boot_trace_out 'I'
	boot_trace_out 'S'
	boot_trace_out 13
	boot_trace_out 10
	call boot_trace_flush
	gget pc, 39

boot_trace_stop_tick
	gget v2, 62
	seth v2, 0              ; fatal stops remain visible after guest TX
	gset v2, 62
boot_trace_tick
	gget v2, 62
	blt boot_trace_return, v2, 0
	set sp, $f004
	ldr v2, sp, 0
	gget v3, 61
	sub v3, v2, v3
	ldi8 sp, 50
	bltu boot_trace_return, v3, sp
	gset v2, 61
	ldi8 v2, 'G'
	jmp boot_trace_state
boot_trace_return
	ret

boot_trace_report
	gget sp, 62
	bge boot_trace_state, sp, 0
	set sp, $f008
	ret
boot_trace_state
	gset lr, 39
	gset v0, 12
	gset v1, 13
	set sp, $f00c
	clr v0
	str v0, sp, 0            ; also expose UART on fatal errors in bank-1 I/O
	call boot_trace_putc
	boot_trace_word 62
	boot_trace_word 59
	boot_trace_word 58
	boot_trace_word 57
	boot_trace_word 40
	boot_trace_word 41
	boot_trace_word 42
	boot_trace_word 46
	boot_trace_word 6
	boot_trace_word 7
	boot_trace_word 8
	boot_trace_word 9
	boot_trace_word 10
	boot_trace_word 12
	boot_trace_word 13
	boot_trace_out 13
	boot_trace_out 10
	call boot_trace_flush
	gget v0, 12
	gget v1, 13
	set sp, $f008
	gget pc, 39

; Hex/output use only V0/V1/V2/SP; no stack, FRAM, guest access or timer.
boot_trace_hex
	gset lr, 18
	mov v1, v2
	shr v2, v1, 12
	call boot_trace_nibble
	shr v2, v1, 8
	call boot_trace_nibble
	shr v2, v1, 4
	call boot_trace_nibble
	mov v2, v1
	call boot_trace_nibble
	gget pc, 18
boot_trace_nibble
	and v2, v2, 15
	ldi8 v0, '0'
	ltu v2, 10
	ldi8 v0, 'A'-10
	add v2, v2, v0
boot_trace_putc
	set sp, $f000
boot_trace_putc_wait
	ldr v0, sp, 0
	bmask_clear boot_trace_putc_wait, v0, 2
	strl v2, sp, 2
	ret
boot_trace_flush
	set sp, $f000
boot_trace_flush_wait
	ldr v0, sp, 0
	bmask_clear boot_trace_flush_wait, v0, 2
	ret

; SD CRC16, low byte of V0; preserve V0/V1/V3, update V4, clobber V2/SP.
boot_trace_crc_byte
	shl v2, v0, 8
	xor v4, v4, v2
	ldi8 v2, 8
boot_trace_crc_bit
	blt boot_trace_crc_xor, v4, 0
	shl v4, v4, 1
	b boot_trace_crc_next
boot_trace_crc_xor
	shl v4, v4, 1
	set sp, $1021
	xor v4, v4, sp
boot_trace_crc_next
	dec v2
	cbnz v2, boot_trace_crc_bit
	set sp, $f008
	ret

boot_trace_crc_bad
	ldi8 v2, 'X'
	call boot_trace_state
	jmp rh11_sd_error
boot_trace_cache_bad
	gset v1, 57
	mov v1, v2
	ldi8 v2, 'K'
	b boot_trace_fram_bad
boot_trace_dma_bad
	mov v0, v3
	mov v1, v2
	ldi8 v2, 'M'
boot_trace_fram_bad
	; Failed FRAM cannot be used as a stack. Release both bank and SD CS,
	; retain the bad offset/status, and stop before executing corrupted code.
	set sp, $f008
	clr v3
	str v3, sp, 4
	ldi8 v3, 3
	str v3, sp, 2
	ldr v3, sp, 0
	ldi8 v3, 6
	gset v3, 10
	call boot_trace_state
boot_trace_fram_stop
	call boot_trace_stop_tick
	b boot_trace_fram_stop

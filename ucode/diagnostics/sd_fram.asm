; HC1200 wire-level diagnostics. No PDP-11 code or FRAM-resident stack.
; Same native ABI and RTL as the SD autoboot build, UART 115200 8N1.
; Power-on/R: read-only FRAM dump + SDHC initialization/read/CRC at both speeds.
; W: explicitly requested FRAM word/byte/address/bank test, save and restore
;    8 bytes at 00200..00207 and 10200..10207 (physical HEX addresses).
; Any other received character is echoed. The menu repeats every second.
; SD commands are ONLY 0,8,55,41,58,17; this image cannot write the card.
;
; Context: 0 SD speed; 1 R1; 2 stage; 3 tick; 4 init bound; 5/6 CRC;
; 16..31 SD first 16 bytes; 32..39 FRAM backups; 48 index; 49 pattern;
; 50 mismatch; 51 pass; 52 actual; 53 saved mismatch; 54 hex index;
; 55 compare LR; 56/57 hex16 LR/value; 58/59 hex8 LR/value;
; 60 message LR; 61 SD command LR; 62 SD test LR; 63 FRAM test LR.
; Do not use context 10/11/15 as scratch: native cause/event/reset controls.

cpu ucode
include ../v2/pseudo.inc

macro out
	ldi8 v0, #1
	call putc
endm
macro crlf
	out 13
	out 10
endm
macro require_sd
	eq #1, #2
	jmp sd_failed
endm

org 0
	jmp start
bus_error_entry
	jmp bus_error

start
	set sp, $f00c
	clr v0
	str v0, sp, 0           ; bank 0 exposes UART services
	set sp, $f006
	ldi8 v0, 1
	str v0, sp, 0           ; reset UART, no break or internal loopback
repeat_tests
	call banner
	call fram_dump
	call sd_test
menu
	call prompt
	set sp, $f004
	ldr v3, sp, 0
	gset v3, 3
menu_poll
	set sp, $f000
	ldr v0, sp, 0
	btc v0, 1
	b menu_input
	ldr v0, sp, 4
	gget v3, 3
	sub v0, v0, v3
	ldi8 v3, 50
	bltu menu_poll, v0, v3
	b menu
menu_input
	ldr v0, sp, 2
	ldi8 v3, 'R'
	ne v0, v3
	jmp repeat_tests
	ldi8 v3, 'r'
	ne v0, v3
	jmp repeat_tests
	ldi8 v3, 'W'
	beq menu_write, v0, v3
	ldi8 v3, 'w'
	beq menu_write, v0, v3
	call putc               ; RX echo also verifies the terminal's TX path
	b menu_poll
menu_write
	call fram_test
	jmp menu

; Output deliberately does not touch FRAM/SD/ticks. v0 byte, v1/v2 volatile;
; v3/v4/sp preserved. A missing card or FRAM cannot hide the startup banner.
putc
	set v2, $f000
putc_wait
	ldr v1, v2, 0
	bts v1, 2
	b putc_wait
	strl v0, v2, 2
	ret
hex_nibble
	and v0, v0, 15
	ldi8 v1, '0'
	ltu v0, 10
	ldi8 v1, 'A'-10
	add v0, v0, v1
	jmp putc
hex8
	gset lr, 58
	gset v0, 59
	shr v0, v0, 4
	call hex_nibble
	gget v0, 59
	call hex_nibble
	gget pc, 58
hex16
	gset lr, 56
	gset v0, 57
	shr v0, v0, 8
	call hex8
	gget v0, 57
	call hex8
	gget pc, 56
banner
	gset lr, 60
	crlf
	out 'H'
	out 'C'
	out '1'
	out '2'
	out '0'
	out '0'
	out ' '
	out 'D'
	out 'I'
	out 'A'
	out 'G'
	out ' '
	out '1'
	out '1'
	out '5'
	out '2'
	out '0'
	out '0'
	out ' '
	out '8'
	out 'N'
	out '1'
	crlf
	gget pc, 60
prompt
	gset lr, 60
	out 'A'
	out 'L'
	out 'I'
	out 'V'
	out 'E'
	out ' '
	out 'R'
	out '='
	out 'r'
	out 'e'
	out 'a'
	out 'd'
	out ' '
	out 'W'
	out '='
	out 'F'
	out 'R'
	out 'A'
	out 'M'
	out '-'
	out 'w'
	out 'r'
	out 'i'
	out 't'
	out 'e'
	crlf
	gget pc, 60
pass
	gset lr, 60
	out 'P'
	out 'A'
	out 'S'
	out 'S'
	crlf
	gget pc, 60
fail
	gset lr, 60
	out 'F'
	out 'A'
	out 'I'
	out 'L'
	crlf
	gget pc, 60
fram_label
	gset lr, 60
	out 'F'
	out 'R'
	out 'A'
	out 'M'
	out ' '
	gget pc, 60

; v4 index 0..7 -> 4 words at 0200 in each 64-KiB bank. v0 data.
; The bank is ALWAYS cleared before returning, so UART cannot hit FRAM.
fram_address
	shr v2, v4, 2
	set sp, $f00c
	str v2, sp, 0
	and v2, v4, 3
	shl v2, v2, 1
	set sp, $0200
	add sp, sp, v2
	ret
fram_bank_zero
	set v2, $f00c
	clr v1
	str v1, v2, 0
	ret
fram_dump
	gset lr, 63
	call fram_label
	out 'R'
	out 'E'
	out 'A'
	out 'D'
	out ':'
	out ' '
	clr v4
fram_dump_loop
	call fram_address
	ldr v0, sp, 0
	call fram_bank_zero
	call hex16
	out ' '
	inc v4
	bne fram_dump_loop, v4, 8
	crlf                      ; a dump is NOT reported as a successful R/W test
	gget pc, 63

fram_test
	gset lr, 63
	call fram_label
	out 'R'
	out '/'
	out 'W'
	out ' '
	out '0'
	out '2'
	out '0'
	out '0'
	out '-'
	out '0'
	out '2'
	out '0'
	out '7'
	out ' '
	out 'B'
	out '0'
	out '+'
	out 'B'
	out '1'
	crlf
	clr v4
fram_save
	call fram_address
	ldr v0, sp, 0
	call fram_bank_zero
	ldi8 v2, 32
	add v2, v2, v4
	gsetr v0, v2
	inc v4
	bne fram_save, v4, 8
	clr v0
	gset v0, 50
	gset v0, 51
fram_pass
	gget v0, 51
	set v3, $0000
	ne v0, 1
	seth v3, $ff
	ne v0, 1
	setl v3, $ff
	ne v0, 2
	seth v3, $55
	ne v0, 2
	setl v3, $aa
	ne v0, 3
	seth v3, $aa
	ne v0, 3
	setl v3, $55
	gset v3, 49
	clr v4
fram_write_loop
	call fram_address
	xor v0, v3, v4          ; different patterns expose bank/address aliases
	str v0, sp, 0
	call fram_bank_zero
	inc v4
	bne fram_write_loop, v4, 8
	clr v4
fram_check_loop
	call fram_address
	ldr v0, sp, 0
	call fram_bank_zero
	gget v3, 49
	xor v3, v3, v4
	call fram_compare
	inc v4
	bne fram_check_loop, v4, 8
	gget v0, 51
	inc v0
	gset v0, 51
	bne fram_pass, v0, 4
	clr v4
fram_bytes
	call fram_address
	ldi8 v0, $a5
	strl v0, sp, 0
	ldi8 v0, $5a
	strl v0, sp, 1
	ldr v0, sp, 0
	call fram_bank_zero
	set v3, $5aa5
	call fram_compare
	inc v4
	bne fram_bytes, v4, 8
	gget v0, 50
	gset v0, 53
	clr v4
fram_restore
	ldi8 v2, 32
	add v2, v2, v4
	ggetr v0, v2
	call fram_address
	str v0, sp, 0
	call fram_bank_zero
	inc v4
	bne fram_restore, v4, 8
	clr v0
	gset v0, 50
	clr v4
fram_restore_check
	call fram_address
	ldr v0, sp, 0
	call fram_bank_zero
	ldi8 v2, 32
	add v2, v2, v4
	ggetr v3, v2
	call fram_compare
	inc v4
	bne fram_restore_check, v4, 8
	call fram_label
	out 'R'
	out '/'
	out 'W'
	out ' '
	gget v0, 53
	cbnz v0, fram_test_bad
	call pass
	b fram_restore_report
fram_test_bad
	call fail
fram_restore_report
	call fram_label
	out 'R'
	out 'E'
	out 'S'
	out 'T'
	out 'O'
	out 'R'
	out 'E'
	out ' '
	gget v0, 50
	cbnz v0, fram_restore_bad
	call pass
	gget pc, 63
fram_restore_bad
	call fail
	gget pc, 63

; Report the first mismatch only; always continue through the restore path.
; v0 actual, v3 expected, v4 index. v3/v4 preserved.
fram_compare
	ne v0, v3
	ret
	gset lr, 55
	gset v0, 52
	gget v0, 50
	bne fram_compare_done, v0, 0
	ldi8 v0, 1
	gset v0, 50
	call fram_label
	out 'B'
	out 'A'
	out 'D'
	out ' '
	out 'i'
	out '='
	mov v0, v4
	call hex8
	out ' '
	out 'E'
	out '='
	mov v0, v3
	call hex16
	out ' '
	out 'G'
	out '='
	gget v0, 52
	call hex16
	crlf
fram_compare_done
	gget pc, 55

; SD command: v0 command, v3:v4 argument -> v0 R1. Bounded Ncr poll.
; Only sd_test calls this, so the fixed context return slot cannot nest.
sd_end
	set sp, $f008
	gget v2, 0
	or v2, v2, 1
	str v2, sp, 2
	ldr v2, sp, 0
	ret
sd_command
	gset lr, 61
	call sd_end
	gget v2, 0
	str v2, sp, 2
	ldr v2, sp, 0
	ldi8 v2, $40
	or v2, v0, v2
	strl v2, sp, 0
	shr v2, v3, 8
	strl v2, sp, 0
	strl v3, sp, 0
	shr v2, v4, 8
	strl v2, sp, 0
	strl v4, sp, 0
	ldi8 v2, 1
	ne v0, 0
	ldi8 v2, $95
	ne v0, 8
	ldi8 v2, $87
	strl v2, sp, 0
	ldi8 v1, 16
sd_response
	ldr v0, sp, 0
	ldi8 v2, $80
	bts v0, v2
	b sd_response_done
	dec v1
	cbnz v1, sd_response
sd_response_done
	gset v0, 1
	gget pc, 61
sd_r1
	gset lr, 60
	out ' '
	out 'R'
	out '1'
	out '='
	gget v0, 1
	call hex8
	crlf
	gget v0, 1
	gget pc, 60

sd_test
	gset lr, 62
	clr v0
	gset v0, 0             ; slow SPI (26.6 MHz / 136 = 195.6 kHz)
	gset v0, 2
	call sd_end
	; >30 ms at the board clock, independent of the tick/UART/FRAM.
	set v4, $ffff
sd_settle
	dec v4
	cbnz v4, sd_settle
	ldi8 v4, 10
sd_power_clocks
	ldr v0, sp, 0
	dec v4
	cbnz v4, sd_power_clocks
	out 'S'
	out 'D'
	out ' '
	out 'C'
	out 'M'
	out 'D'
	out '0'
	clr v0
	clr v3
	clr v4
	call sd_command
	call sd_r1
	require_sd v0, 1
	ldi8 v0, 8
	gset v0, 2
	out 'S'
	out 'D'
	out ' '
	out 'C'
	out 'M'
	out 'D'
	out '8'
	ldi8 v0, 8
	clr v3
	set v4, $01aa
	call sd_command
	call sd_r1
	require_sd v0, 1
	; Print all four R7 bytes, then validate the full echo pattern.
	clr v3
	clr v4
	ldr v0, sp, 0
	shl v3, v0, 8
	ldr v0, sp, 0
	or v3, v3, v0
	ldr v0, sp, 0
	shl v4, v0, 8
	ldr v0, sp, 0
	or v4, v4, v0
	out 'R'
	out '7'
	out '='
	mov v0, v3
	call hex16
	mov v0, v4
	call hex16
	crlf
	require_sd v3, 0
	set v0, $01aa
	require_sd v4, v0
	ldi8 v0, 41
	gset v0, 2
	set v0, 4096
	gset v0, 4
	set sp, $f004
	ldr v0, sp, 0
	gset v0, 3
	out 'S'
	out 'D'
	out ' '
	out 'A'
	out 'C'
	out 'M'
	out 'D'
	out '4'
	out '1'
sd_init_loop
	ldi8 v0, 55
	clr v3
	clr v4
	call sd_command
	ldi8 v2, 1
	geu v2, v0
	jmp sd_failed
	ldi8 v0, 41
	set v3, $4000
	clr v4
	call sd_command
	cbz v0, sd_init_ready
	require_sd v0, 1
	call sd_end
	set sp, $f004
	ldr v0, sp, 0
	gget v2, 3
	sub v0, v0, v2
	ldi8 v2, 100            ; 2-second bound; counter also bounds broken ticks
	ltu v0, v2
	jmp sd_failed
	gget v0, 4
	dec v0
	gset v0, 4
	bne sd_init_loop, v0, 0
	jmp sd_failed
sd_init_ready
	call sd_r1
	ldi8 v0, 58
	gset v0, 2
	out 'S'
	out 'D'
	out ' '
	out 'C'
	out 'M'
	out 'D'
	out '5'
	out '8'
	ldi8 v0, 58
	clr v3
	clr v4
	call sd_command
	call sd_r1
	require_sd v0, 0
	ldr v0, sp, 0
	shl v3, v0, 8
	ldr v0, sp, 0
	or v3, v3, v0
	ldr v0, sp, 0
	shl v4, v0, 8
	ldr v0, sp, 0
	or v4, v4, v0
	out 'O'
	out 'C'
	out 'R'
	out '='
	mov v0, v3
	call hex16
	mov v0, v4
	call hex16
	crlf
	set v0, $c000
	and v3, v3, v0
	require_sd v3, v0       ; powered-up SDHC/SDXC, same contract as autoboot
	out 'S'
	out 'D'
	out ' '
	out 'S'
	out 'L'
	out 'O'
	out 'W'
	b sd_read
sd_fast
	call sd_end
	ldi8 v0, 2
	gset v0, 0             ; fast SPI (26.6 MHz / 4 = 6.65 MHz)
	out 'S'
	out 'D'
	out ' '
	out 'F'
	out 'A'
	out 'S'
	out 'T'
sd_read
	ldi8 v0, 17
	gset v0, 2
	clr v3
	clr v4                  ; physical LBA 0, no partition offset
	call sd_command
	call sd_r1
	require_sd v0, 0
	set v4, $ffff
sd_token_wait
	ldr v0, sp, 0
	ldi8 v2, $ff
	bne sd_token, v0, v2
	dec v4
	cbnz v4, sd_token_wait
sd_token
	gset v0, 1
	out 'T'
	out 'O'
	out 'K'
	out 'E'
	out 'N'
	out '='
	gget v0, 1
	call hex8
	crlf
	gget v0, 1
	ldi8 v2, $fe
	require_sd v0, v2
	clr v3                  ; SD CRC16: polynomial 1021, initial value 0000
	clr v4                  ; byte index
sd_bytes
	ldr v0, sp, 0
	ldi8 v2, 16
	geu v4, v2
	b sd_keep_byte
	b sd_crc_byte
sd_keep_byte
	add v2, v2, v4
	gsetr v0, v2
sd_crc_byte
	shl v0, v0, 8
	xor v3, v3, v0
	ldi8 v1, 8
sd_crc_bit
	mov v2, v3
	shl v3, v3, 1
	ge v2, 0
	b sd_crc_xor
	b sd_crc_next
sd_crc_xor
	set v2, $1021
	xor v3, v3, v2
sd_crc_next
	dec v1
	cbnz v1, sd_crc_bit
	inc v4
	set v2, 512
	bne sd_bytes, v4, v2
	gset v3, 5
	ldr v0, sp, 0
	shl v4, v0, 8
	ldr v0, sp, 0
	or v4, v4, v0
	gset v4, 6
	call sd_end
	out 'C'
	out 'R'
	out 'C'
	out '='
	mov v0, v3
	call hex16
	out '/'
	mov v0, v4
	call hex16
	out ' '
	require_sd v3, v4
	call pass
	out 'D'
	out 'A'
	out 'T'
	out 'A'
	out '='
	ldi8 v4, 16
sd_dump
	ggetr v0, v4
	call hex8
	out ' '
	inc v4
	ldi8 v2, 32
	bne sd_dump, v4, v2
	crlf
	gget v0, 0
	eq v0, 0
	b sd_done
	jmp sd_fast
sd_done
	gget pc, 62
sd_failed
	call sd_end
	crlf
	out 'S'
	out 'D'
	out ' '
	out 'F'
	out 'A'
	out 'I'
	out 'L'
	out ' '
	out 's'
	out 't'
	out 'a'
	out 'g'
	out 'e'
	out '='
	gget v0, 2
	call hex8              ; command number in HEX: 00,08,29,3A,11
	crlf
	gget pc, 62
bus_error
	set sp, $f00c
	clr v0
	str v0, sp, 0
	out 'B'
	out 'U'
	out 'S'
	out ' '
	call fail
	jmp menu

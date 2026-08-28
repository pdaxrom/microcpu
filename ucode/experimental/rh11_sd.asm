; EXPERIMENTAL RK611-at-RH11 / SDHC transport. Included only by disk build.
; Context 40..55 corresponds to the 16 RH registers, 56 flags (SD ready=1,
; IRQ=2, DMA active=4, write=8), 57 sector offset, 58/59 LBA low/high,
; 60 timeout start, 63 peripheral return. At instruction boundaries only,
; scratch 25..30 is reused; never call guest memory helpers from this code.
; One 512-byte cache at FRAM bank 1 offset 0, inaccessible to guest DMA.

rh11_reset
	clr v2
	ldi8 sp, 40
	ldi8 v4, 63
rh11_clear_loop
	gsetr v2, sp
	inc sp
	bne rh11_clear_loop, sp, v4
	ldi8 v2, $80
	gset v2, 40
	ldi8 v2, $40
	gset v2, 44
	set v2, $81c1
	gset v2, 45
	set sp, $f008
	clr v2
	str v2, sp, 4
	ldi8 v2, 1
	str v2, sp, 2
	ret

; memory_access ABI: v4=address, v3=write data, lr=access mode.
rh11_io
	shr sp, v4, 1
	and sp, sp, 15
	ldi8 v2, 40
	add sp, sp, v2
	ggetr v2, sp
	bmask_clear rh11_io_read, lr, 1
	bmask_clear rh11_io_word, lr, 2
	bmask_clear rh11_io_byte_low, v4, 1
	shl v3, v3, 8
	seth v2, 0
	or v3, v3, v2
	b rh11_io_word
rh11_io_byte_low
	setl v2, 0
	seth v3, 0
	or v3, v3, v2
rh11_io_word
	ldi8 v2, 40
	beq rh11_cs1, sp, v2
	ldi8 v2, 44
	beq rh11_cs2, sp, v2
	ldi8 v2, 45
	beq rh11_io_ignore, sp, v2
	inc v2
	beq rh11_io_ignore, sp, v2
	ldi8 v2, 52
	bgeu rh11_io_ignore, sp, v2
	ldi8 v2, 42
	bne rh11_io_store, sp, v2
	set v2, $fffe
	and v3, v3, v2
rh11_io_store
	gsetr v3, sp
rh11_io_ignore
	jmp memory_restore
rh11_io_read
	bmask_clear rh11_io_result, lr, 2
	bmask_clear rh11_io_read_low, v4, 1
	shr v2, v2, 8
rh11_io_read_low
	seth v2, 0
rh11_io_result
	mov v4, v2
	jmp memory_return

rh11_cs2
	bmask_clear rh11_cs2_low, v4, 1
	jmp memory_restore
rh11_cs2_low
	ldi8 v2, $20
	bmask_set rh11_io_reset, v3, v2
	ldi8 v2, $17
	and v3, v3, v2
	ldi8 v2, $40
	or v3, v3, v2
	gset v3, 44
	jmp memory_restore
rh11_cs1
	blt rh11_io_reset, v3, 0
	gget v2, 40
	; High-byte writes change BA16/17 only, never restart a low-byte GO.
	bmask_clear rh11_cs1_low, v4, 1
	set v4, $300
	and v3, v3, v4
	seth v2, 0
	or v3, v3, v2
	gset v3, 40
	jmp memory_restore
rh11_cs1_low
	; IE disable cancels the private request; IE+RDY rising requests one IRQ.
	gget v4, 56
	set sp, $fffd
	and v4, v4, sp
	ldi8 sp, $40
	bmask_clear rh11_cs1_irq_known, v3, sp
	bmask_set rh11_cs1_irq_old, v2, sp
	ldi8 sp, $80
	bmask_clear rh11_cs1_irq_known, v3, sp
	or v4, v4, 2
	b rh11_cs1_irq_known
rh11_cs1_irq_old
	gget v4, 56
rh11_cs1_irq_known
	gset v4, 56
	set sp, $37f
	and v4, v3, sp
	set sp, $8080
	and v2, v2, sp
	or v4, v4, v2
	bmask_clear rh11_cs1_store, v3, 1
	set sp, $37f
	and v4, v4, sp
	clr v2
	gset v2, 46
	gset v2, 47
	gget v2, 44
	ldi8 sp, $57
	and v2, v2, sp
	gset v2, 44
	gget v2, 56
	and v2, v2, 1
	gset v2, 56
rh11_cs1_store
	gset v4, 40
	jmp memory_restore
rh11_io_reset
	call rh11_reset
	jmp memory_restore

; Called after GO at an instruction boundary. Transfers are synchronous in
; this first prototype: guest execution resumes after completion/error.
rh11_poll
	gset lr, 25
	gset v0, 26
	gset v1, 27
	clr v2
	gset v2, 57
	gget v2, 56
	or v2, v2, 4
	gset v2, 56
	gget v0, 40
	ldi8 v2, $3e
	and v0, v0, v2
	ldi8 v2, $10
	bltu rh11_finish, v0, v2
	beq rh11_read, v0, v2
	ldi8 v2, $38
	beq rh11_read, v0, v2
	ldi8 v2, $12
	beq rh11_write, v0, v2
	ldi8 v2, $30
	beq rh11_write, v0, v2
	ldi8 v2, 1
	gset v2, 46              ; unsupported function, not silent success
	jmp rh11_finish
rh11_write
	gget v2, 56
	or v2, v2, 8
	gset v2, 56
rh11_read
	gget v0, 44
	and v0, v0, 7
	bne rh11_no_drive, v0, 0
	gget v0, 41
	bge rh11_finish, v0, 0
	gget v0, 56
	bmask_set rh11_sector, v0, 1
	call sd_initialize
rh11_sector
	; Full 24-bit LBA = DC*66 + head*22 + sector, using native carry.
	gget v0, 43
	ldi8 v2, 31
	and v1, v0, v2
	ldi8 v2, 22
	bgeu rh11_bad_geometry, v1, v2
	shr v0, v0, 8
	and v0, v0, 7
	bgeu rh11_bad_geometry, v0, 3
	shl v2, v0, 4
	shl v3, v0, 2
	add v2, v2, v3
	shl v0, v0, 1
	add v2, v2, v0
	add v1, v1, v2
	gget v0, 48
	shr v3, v0, 10
	shl v4, v0, 6
	shr v2, v0, 15
	add v3, v3, v2
	shl v0, v0, 1
	add v4, v4, v0
	adc v3, v3, 0
	add v4, v4, v1
	adc v3, v3, 0
	gset v4, 58
	gset v3, 59
	clr v0
	gset v0, 57
	call sd_read_sector      ; no dirty guest words until the cache is valid
rh11_dma
	gget v1, 42
	set v2, $e000
	bgeu rh11_nem, v1, v2
	gget v2, 40
	set v3, $300
	bmask_set rh11_nem, v2, v3
	gget v0, 57
	set sp, $f008
	gget v2, 56
	bmask_set rh11_dma_write, v2, 8
	ldi8 v2, 1
	str v2, sp, 4
	ldr v3, v0, 0
	clr v2
	str v2, sp, 4
	str v3, v1, 0
	b rh11_dma_advance
rh11_dma_write
	ldr v3, v1, 0
	ldi8 v2, 1
	str v2, sp, 4
	str v3, v0, 0
	clr v2
	str v2, sp, 4
rh11_dma_advance
	add v0, v0, 2
	gset v0, 57
	gget v2, 44
	ldi8 v3, $10
	bmask_set rh11_dma_no_ba, v2, v3
	add v1, v1, 2
	gset v1, 42
rh11_dma_no_ba
	gget v1, 41
	inc v1
	gset v1, 41
	cbz v1, rh11_dma_flush
	set v2, 512
	bne rh11_dma, v0, v2
rh11_dma_flush
	gget v2, 56
	bmask_clear rh11_dma_flushed, v2, 8
	call sd_write_sector
rh11_dma_flushed
	gget v0, 57
	set v2, 512
	bne rh11_finish, v0, v2
	gget v0, 43
	ldi8 v2, 31
	and v1, v0, v2
	inc v1
	ldi8 v2, 22
	bne rh11_advance_store, v1, v2
	set v2, $f8e0
	and v1, v0, v2
	shr v0, v0, 8
	and v0, v0, 7
	inc v0
	bltu rh11_advance_head, v0, 3
	clr v0
	gget v2, 48
	inc v2
	gset v2, 48
rh11_advance_head
	shl v0, v0, 8
	or v1, v1, v0
	b rh11_advance_done
rh11_advance_store
	set v2, $ffe0
	and v0, v0, v2
	or v1, v1, v0
rh11_advance_done
	gset v1, 43
	gget v0, 41
	fbne rh11_sector, v0, 0
	jmp rh11_finish

rh11_bad_geometry
	set v2, $400
	gset v2, 46
	b rh11_finish
rh11_no_drive
	gget v2, 44
	set v3, $1000
	or v2, v2, v3
	gset v2, 44
	b rh11_finish
rh11_bus_error
	gget sp, 56
	bmask_set rh11_nem, sp, 4
	jmp cpu_bus_error
rh11_nem
	set sp, $f008
	clr v2
	str v2, sp, 4
	gset v2, 10              ; DMA errors do not trap the guest CPU
	gget v2, 44
	set v3, $800
	or v2, v2, v3
	gset v2, 44
	ldi8 v2, 2
	gset v2, 46
	; Match reference partial-write semantics: commit successfully read words.
	gget v2, 56
	bmask_clear rh11_finish, v2, 8
	gget v2, 57
	cbz v2, rh11_finish
	call sd_write_sector
	b rh11_finish
rh11_sd_error
	gget v2, 44
	set v3, $8000
	or v2, v2, v3
	gset v2, 44              ; data-late/transport failure
	set v2, $2000
	gset v2, 46
	gget v2, 56
	and v2, v2, 14           ; retry must reinitialize the card
	gset v2, 56
rh11_finish
	call sd_end
	gget v0, 40
	set v2, $fffe
	and v0, v0, v2
	ldi8 v2, $80
	or v0, v0, v2
	gget v1, 46
	cbz v1, rh11_finish_no_er
	set v2, $8000
	or v0, v0, v2
rh11_finish_no_er
	gget v1, 44
	set v2, $ff80
	bmask_clear rh11_finish_status, v1, v2
	set v2, $8000
	or v0, v0, v2
rh11_finish_status
	gset v0, 40
	gget v1, 56
	and v1, v1, 1
	ldi8 v2, $40
	bmask_clear rh11_finish_irq, v0, v2
	or v1, v1, 2
rh11_finish_irq
	gset v1, 56
	gget v0, 26
	gget v1, 27
	gget pc, 25

; Close transaction, restore guest FRAM bank, supply trailing clocks.
sd_end
	set sp, $f008
	clr v2
	str v2, sp, 4
	gget v2, 56
	and v2, v2, 1
	shl v2, v2, 1
	or v2, v2, 1
	str v2, sp, 2
	ldr v2, sp, 0
	ret

; CMD(v0, v3:v4) -> R1 in v0. CS remains selected. v1/v2/sp volatile.
sd_command
	gset lr, 30
	set sp, $f008
	gget v2, 56
	and v2, v2, 1
	shl v2, v2, 1
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
	cbnz v0, sd_command_not_reset
	ldi8 v2, $95
sd_command_not_reset
	bne sd_command_crc, v0, 8
	ldi8 v2, $87
sd_command_crc
	strl v2, sp, 0
	ldi8 v1, 16
sd_command_response
	ldr v0, sp, 0
	ldi8 v2, $80
	bmask_clear sd_command_done, v0, v2
	dec v1
	cbnz v1, sd_command_response
	jmp rh11_sd_error
sd_command_done
	gget pc, 30

sd_initialize
	gset lr, 28
	; Wait at least one complete 60-Hz interval before the first power-up
	; clocks. Two tick transitions avoid a nearly-zero boundary interval.
	set sp, $f004
	ldr v0, sp, 0
sd_power_settle
	ldr v2, sp, 0
	sub v2, v2, v0
	bltu sd_power_settle, v2, 2
	call sd_end
	ldi8 v1, 10
sd_power_clocks
	ldr v0, sp, 0
	dec v1
	cbnz v1, sd_power_clocks
	clr v0
	clr v3
	clr v4
	call sd_command
	fbne rh11_sd_error, v0, 1
	call sd_end
	ldi8 v0, 8
	clr v3
	set v4, $1aa
	call sd_command
	fbne rh11_sd_error, v0, 1
	ldr v0, sp, 0
	fbne rh11_sd_error, v0, 0
	ldr v0, sp, 0
	fbne rh11_sd_error, v0, 0
	ldr v0, sp, 0
	fbne rh11_sd_error, v0, 1
	ldr v0, sp, 0
	ldi8 v2, $aa
	fbne rh11_sd_error, v0, v2
	call sd_end
	set sp, $f004
	ldr v0, sp, 0
	gset v0, 60
sd_initialize_wait
	ldi8 v0, 55
	clr v3
	clr v4
	call sd_command
	ldi8 v2, 1
	bltu sd_initialize_bad, v2, v0
	call sd_end
	ldi8 v0, 41
	set v3, $4000
	clr v4
	call sd_command
	cbz v0, sd_initialize_ready
	fbne rh11_sd_error, v0, 1
	call sd_end
	set sp, $f004
	ldr v0, sp, 0
	gget v2, 60
	sub v0, v0, v2
	ldi8 v2, 120
	bltu sd_initialize_wait, v0, v2
sd_initialize_bad
	jmp rh11_sd_error
sd_initialize_ready
	call sd_end
	ldi8 v0, 58
	clr v3
	clr v4
	call sd_command
	fbne rh11_sd_error, v0, 0
	ldr v0, sp, 0
	ldi8 v2, $c0
	and v0, v0, v2
	fbne rh11_sd_error, v0, v2 ; SDHC/SDXC block addressing required
	ldr v0, sp, 0
	ldr v0, sp, 0
	ldr v0, sp, 0
	gget v0, 56
	or v0, v0, 1
	gset v0, 56
	call sd_end
	gget pc, 28

sd_read_sector
	gset lr, 29
	ldi8 v0, 17
	gget v3, 59
	gget v4, 58
	call sd_command
	fbne rh11_sd_error, v0, 0
	set sp, $f004
	ldr v0, sp, 0
	gset v0, 60
sd_read_token
	set sp, $f008
	ldr v0, sp, 0
	ldi8 v2, $fe
	beq sd_read_data, v0, v2
	ldi8 v2, $ff
	fbne rh11_sd_error, v0, v2
	set sp, $f004
	ldr v0, sp, 0
	gget v2, 60
	sub v0, v0, v2
	ldi8 v2, 120
	bltu sd_read_token, v0, v2
	jmp rh11_sd_error
sd_read_data
	ldi8 v2, 1
	str v2, sp, 4
	clr v1
	set v3, 512
sd_read_bytes
	ldr v0, sp, 0
	ldr v2, sp, 0
	shl v2, v2, 8
	or v0, v0, v2
	str v0, v1, 0
	add v1, v1, 2
	bne sd_read_bytes, v1, v3
	ldr v0, sp, 0           ; CRC disabled in SPI default mode
	ldr v0, sp, 0
	call sd_end
	gget pc, 29

sd_write_sector
	gset lr, 29
	ldi8 v0, 24
	gget v3, 59
	gget v4, 58
	call sd_command
	fbne rh11_sd_error, v0, 0
	ldi8 v0, $fe
	strl v0, sp, 0
	ldi8 v2, 1
	str v2, sp, 4
	clr v1
	set v3, 512
sd_write_bytes
	ldr v0, v1, 0
	strl v0, sp, 0
	shr v0, v0, 8
	strl v0, sp, 0
	add v1, v1, 2
	bne sd_write_bytes, v1, v3
	ldi8 v0, $ff
	strl v0, sp, 0
	strl v0, sp, 0
	ldr v0, sp, 0
	ldi8 v2, 31
	and v0, v0, v2
	fbne rh11_sd_error, v0, 5
	clr v2
	str v2, sp, 4
	set sp, $f004
	ldr v0, sp, 0
	gset v0, 60
sd_write_busy
	set sp, $f008
	ldr v0, sp, 0
	ldi8 v2, $ff
	beq sd_write_done, v0, v2
	set sp, $f004
	ldr v0, sp, 0
	gget v2, 60
	sub v0, v0, v2
	ldi8 v2, 120
	bltu sd_write_busy, v0, v2
	jmp rh11_sd_error
sd_write_done
	; An accepted data token is not the final programming status.
	ldi8 v0, 13
	clr v3
	clr v4
	call sd_command
	fbne rh11_sd_error, v0, 0
	ldr v0, sp, 0
	fbne rh11_sd_error, v0, 0
	call sd_end
	gget pc, 29

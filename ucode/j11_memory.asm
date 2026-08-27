; Raw transfers are confined to this dispatcher (and native peripheral I/O).
; Mode: bit 0 write, bit 1 byte, bit 2 instruction fetch.
memory_fetch_word
	gset v3, 27
	set lr, 4
	b memory_access

memory_read_word
	gset v3, 27
	clr lr
	b memory_access

memory_read_byte
	gset v3, 27
	set lr, 2
	b memory_access

memory_write_word
	set lr, 1
	b memory_access

memory_write_byte
	set lr, 3

memory_access
	gset v2, 28
	gset sp, 29
	gget v2, 18
	and v2, v2, 15
	shl sp, lr, 4
	or v2, v2, sp
	gset v2, 18
	; Word alignment is checked before any device side effect.
	bmask_set memory_aligned, lr, 2
	bmask_clear memory_aligned, v4, 1
	far_jump cpu_address_error
memory_aligned
	set sp, $fff8
	and v2, v4, sp
	set sp, $f000
	fbeq bus_error_entry, v2, sp ; never expose the native service window
	set sp, $ff70
	beq memory_console, v2, sp
	set sp, $fffe
	and v2, v4, sp
	set sp, $ff66		; 177546: KDJ11-B line-time clock
	beq memory_device, v2, sp
	set sp, $e000
	bltu memory_raw, v4, sp
	far_jump cpu_io_decode

memory_console
	set sp, $fffe
	and v2, v4, sp
memory_device
	; High bytes are zero and have no low-byte CSR/data side effects.
	bmask_clear memory_device_low, v4, 1
	clr v4
	b memory_return
memory_device_low
	set sp, $ff66
	beq memory_ltc, v2, sp
	set sp, $ff70
	sub v2, v2, sp
	beq memory_rcsr, v2, 0
	beq memory_rbuf, v2, 2
	beq memory_xcsr, v2, 4
	; XBUF reads as zero. Writes submit a byte and clear DONE/request.
	bmask_clear memory_zero, lr, 1
	set sp, $f002
	strl v3, sp, 0
	gget v2, 22
	set sp, $45
	and v2, v2, sp
	gset v2, 22
	b memory_zero

memory_rcsr
	set sp, 20
	b memory_csr
memory_xcsr
	set sp, 22
memory_csr
	ggetr v4, sp
	bmask_clear memory_csr_read, lr, 1
	; A rising IE while DONE is set creates one request, not a level IRQ.
	set v2, $40
	and lr, v3, v2
	and v2, v4, v2
	bne memory_csr_enable_known, lr, v2
	b memory_csr_preserve
memory_csr_enable_known
	beq memory_csr_disable, lr, 0
	set v2, $80
	bmask_clear memory_csr_preserve, v4, v2
	set v2, $100
	or v4, v4, v2
	b memory_csr_preserve
memory_csr_disable
	set v2, $ff
	and v4, v4, v2
memory_csr_preserve
	set v2, $180
	and v4, v4, v2
	or v4, v4, lr
	set v2, 20
	bne memory_xcsr_control, sp, v2
	; RCSR RE clears DONE/request; RE itself always reads as zero.
	bmask_clear memory_csr_store, v3, 1
	mov v4, lr
	b memory_csr_store
memory_xcsr_control
	and v2, v3, 5
	or v4, v4, v2
	; Physical BREAK and loopback are raw controls, not guest registers.
	and v2, v3, 1
	shl v2, v2, 1
	and v3, v3, 4
	or v2, v2, v3
	set lr, $f006
	str v2, lr, 0
memory_csr_store
	gsetr v4, sp
memory_csr_read
	set v2, $ff
	and v4, v4, v2
	b memory_return

memory_rbuf
	gget v4, 21
	seth v4, 0		; high bits hold private PIRQ state
	gget v2, 20
	set sp, $40
	and v2, v2, sp
	gset v2, 20		; low-byte read or write acknowledges received data
	b memory_return

memory_ltc
	gget v4, 23
	bmask_clear memory_ltc_read, lr, 1 ; LCM is NOT read-to-clear on KDJ11-B
	mov v2, v4
	setl v2, 0		; preserve CPUERR in the context word's high byte
	set sp, $80
	and v4, v4, v3		; writing zero clears LCM; one cannot set it
	and v4, v4, sp
	set sp, $40
	and v3, v3, sp
	or v4, v4, v3
	or v4, v4, v2
	gset v4, 23
memory_ltc_read
	seth v4, 0
	b memory_return

memory_zero
	clr v4
	b memory_return

memory_raw
	biteq memory_raw_write, lr, 1
	biteq memory_raw_read_byte, lr, 2
	ldr v4, v4, 0
	b memory_return

memory_raw_read_byte
	ldrl v4, v4, 0
	seth v4, 0
	b memory_return

memory_raw_write
	biteq memory_raw_write_byte, lr, 2
	str v3, v4, 0
	b memory_return

memory_raw_write_byte
	strl v3, v4, 0

memory_return
	gget lr, 18
	shr lr, lr, 4
	bmask_set memory_restore, lr, 1
	gset v4, 18		; stores retain their original NZVC and access mode
memory_restore
	gget v2, 28
	gget v3, 27
	gget v4, 26
	gget sp, 29
	gget lr, 30
	add lr, lr, 7		; mcall saves the address of its first instruction + 1
	gset lr, 30
	gget lr, 25
	gget pc, 30

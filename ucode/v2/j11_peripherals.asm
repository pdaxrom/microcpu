; Software DL11 console and KDJ11-B LTC. Only raw bytes and elapsed ticks are
; obtained from hardware; all CSRs, request latches and arbitration live here.
; Context 20=RCSR, 21=RBUF/PIRQ, 22=XCSR, 23=LTC/CPUERR, 24=last tick.
; UART CSR bit 8 is a private request latch, never visible to guest software.

peripherals_reset
	clr v2
	gset v2, 20
	gset v2, 21
	ldi8 v2, $80
	gset v2, 22
	gget v2, 23
	setl v2, $80		; RESET preserves CPUERR, but clears PIRQ above
	gset v2, 23
	set sp, $f004
	ldr v2, sp, 0
	gset v2, 24
	rts

; Called only at an instruction boundary / WAIT loop, never inside an access
; helper. Preserves v0 (guest PC), v1 (WAIT flag), lr (return address).
peripherals_poll
	; Board notifications use the otherwise ineligible BR0/vector0. Avoid
	; native bus reads on ordinary instructions with no new UART/time event.
	gget v2, 11
	bge peripherals_select, v2, 0
	set v3, $7ff
	and v3, v2, v3
	bne peripherals_select, v3, 0
	set sp, $f000
	ldr v4, sp, 0
	bmask_clear peripherals_tx, v4, 1
	gget v2, 20
	ldi8 v3, $80
	bmask_set peripherals_tx, v2, v3
	ldr v3, sp, 2
	gget sp, 21
	setl sp, 0
	or v3, v3, sp		; received data must not disturb PIRQ requests
	gset v3, 21
	ldi8 v3, $80
	or v2, v2, v3
	ldi8 v3, $40
	bmask_clear peripherals_rx_store, v2, v3
	set v3, $100
	or v2, v2, v3
peripherals_rx_store
	gset v2, 20

peripherals_tx
	bmask_clear peripherals_time, v4, 2
	gget v2, 22
	ldi8 v3, $80
	bmask_set peripherals_time, v2, v3
	or v2, v2, v3
	ldi8 v3, $40
	bmask_clear peripherals_tx_store, v2, v3
	set v3, $100
	or v2, v2, v3
peripherals_tx_store
	gset v2, 22

peripherals_time
	set sp, $f004
	ldr v2, sp, 0
	gget v3, 24
	beq peripherals_select, v2, v3
	gset v2, 24
	gget v2, 23
	ldi8 v3, $80
	or v2, v2, v3
	gset v2, 23

peripherals_select
	gget v2, 11		; retain external requests while software IRQs run
	clr v4
	bge peripherals_select_ltc, v2, 0
	shr v4, v2, 8
	and v4, v4, 7
	bne peripherals_select_ltc, v4, 0
	ldi8 v3, $ff
	and v3, v2, v3
	bne peripherals_select_ltc, v3, 0
	clr v2
	gset v2, 11		; acknowledge only the native BR0 notification
peripherals_select_ltc
	bgtu peripherals_select_uart, v4, 6 ; dedicated EVENT outranks external BR6
	gget v3, 23
	ldi8 sp, $c0
	and v3, v3, sp
	bne peripherals_select_uart, v3, sp
	set v2, $8e40		; software tag bit 11, BR6, vector 100 octal
	b peripherals_selected
peripherals_select_uart
	bgeu peripherals_selected, v4, 4
	set sp, $100
	gget v3, 20
	bmask_clear peripherals_select_tx, v3, sp
	set v2, $8c30		; BR4, RX vector 060 wins over TX
	b peripherals_selected
peripherals_select_tx
	gget v3, 22
	bmask_clear peripherals_selected, v3, sp
	set v2, $8c34		; BR4, TX vector 064
peripherals_selected
	b cpu_interrupt_select

; v2 contains the accepted software request. Do not consume any external IRQ.
peripherals_ack
	ldi8 v3, $ff
	and sp, v2, v3
	ldi8 v3, $a0
	fbeq trap_entry, sp, v3	; PIRQ stays asserted until software clears it
	ldi8 v3, $40
	beq peripherals_ack_ltc, sp, v3
	ldi8 v4, 20
	ldi8 v3, $30
	beq peripherals_ack_uart, sp, v3
	ldi8 v4, 22
peripherals_ack_uart
	ggetr v2, v4
	ldi8 v3, $ff
	and v2, v2, v3		; IRQ acknowledge leaves DONE set
	gsetr v2, v4
	far_jump trap_entry
peripherals_ack_ltc
	gget v2, 23
	set v3, $ff40
	and v2, v2, v3		; clear LCM; retain IE and the separate CPUERR state
	gset v2, 23
	far_jump trap_entry

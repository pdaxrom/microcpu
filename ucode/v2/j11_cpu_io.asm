; DCJ11 processor I/O, entirely in assembly. No cache or MMU is advertised.
; 21[15:9]=PIRQ requests, 21[7:0]=RBUF; 23[15:8]=CPUERR, 23[7:0]=LTC;
; 31=CCR. These share existing context words, not new hardware registers.
; KDJ11-A-compatible identification only, not a complete KDJ11-A board.
; MAINT[7:4]=1; FPA[8] and all other profile bits retain their zero value.
J11_MAINT_VALUE equ $0010

cpu_io_decode
	gget lr, 18
	shr lr, lr, 4
	set sp, $ffe4		; 177744 MEMERR: no parity hardware in this board
	beq memory_zero, v2, sp
	set sp, $ffe8		; 177750 MAINT: read-only module identification
	beq cpu_maint, v2, sp
	set sp, $ffe6
	beq cpu_ccr, v2, sp
	set sp, $ffea
	beq cpu_internal_zero, v2, sp ; 177752: no cache => no hit/miss history
	set sp, $fff6
	beq cpu_error_register, v2, sp
	set sp, $fffa
	beq cpu_pirq, v2, sp
	set sp, $fffe
	beq cpu_psw, v2, sp
	; MMU is ABSENT in this profile, not an implemented but disabled unit.
	; MMR/PAR/PDR addresses must time out on the ordinary unmapped-I/O path.
	; Zero/ignore stubs fool RT-11's bus-trap probe into using MMU mappings and
	; hang its extended-memory sizing loop. No translation is emulated here.
	b memory_raw

cpu_maint
	bmask_set memory_return, lr, 1 ; ignore word and either byte-lane writes
	ldi8 v2, J11_MAINT_VALUE
	b cpu_read_value

cpu_internal_zero
	gget lr, 18
	shr lr, lr, 4
	bmask_set cpu_address_error, lr, 4
	b memory_zero

cpu_ccr
	bmask_set cpu_address_error, lr, 4
	gget v2, 31
	ldi8 sp, 31
	b cpu_register_access

cpu_psw
	bmask_set cpu_address_error, lr, 4
	gget v2, 8
	ldi8 sp, 8
	b cpu_register_access

cpu_pirq
	bmask_set cpu_address_error, lr, 4
	gget v2, 21
	setl v2, 0
	ldi8 sp, 21
	bmask_set cpu_register_write, lr, 1
	shr sp, v2, 9
	clr v3
cpu_pirq_priority
	cbz sp, cpu_pirq_visible
	shr sp, sp, 1
	inc v3
	b cpu_pirq_priority
cpu_pirq_visible
	shl sp, v3, 5
	or v2, v2, sp
	shl sp, v3, 1
	or v2, v2, sp
	b cpu_read_value

cpu_register_access
	bmask_clear cpu_read_value, lr, 1
cpu_register_write
	bmask_clear cpu_register_merged, lr, 2
	seth v3, 0
	bmask_clear cpu_register_low, v4, 1
	shl v3, v3, 8
	seth v2, 0
	b cpu_register_byte
cpu_register_low
	setl v2, 0
cpu_register_byte
	or v3, v3, v2
cpu_register_merged
	beq cpu_psw_write, sp, 8
	ldi8 v2, 21
	beq cpu_pirq_write, sp, v2
	; DCJ11 guide figure 5-1: CCR[15:11] and bit 8 always read zero.
	set v2, $06ff
	and v3, v3, v2
	gset v3, 31
	b memory_return

cpu_pirq_write
	set v2, $fe00
	and v3, v3, v2
	gget v2, 21
	seth v2, 0
	or v3, v3, v2
	gset v3, 21		; low-byte writes leave all requests unchanged
	b memory_return

cpu_psw_write
	gget v2, 8
	ldi8 sp, $10
	and sp, v2, sp
	set lr, $ffef
	and v3, v3, lr
	or v3, v3, sp		; explicit PSW writes cannot change T
	shr v2, v2, 14
	bne cpu_psw_old_mode, v2, 2
	clr v2
cpu_psw_old_mode
	shr v4, v3, 14
	bne cpu_psw_new_mode, v4, 2
	clr v4
cpu_psw_new_mode
	beq cpu_psw_commit, v2, v4
	ldi8 sp, 16
	add v2, v2, sp
	add v4, v4, sp
	gget sp, 6
	gsetr sp, v2
	ggetr sp, v4
	gset sp, 6
cpu_psw_commit
	far_call cpu_commit_psw
	gget v2, 14
	or v2, v2, 8		; suppress the writing instruction's implicit CC
	gset v2, 14
	b memory_return

; Commit v3=effective PSW, swapping active R0..R5 with the inactive set only
; when RS changes. SP banks are handled by the caller; PC is never banked.
; Preserve v0 (fault PC), v1 (IR) and v3; clobber sp/v2/v4 and native flags.
; Own return slot 39 is separate from the non-reentrant memory-helper frame.
cpu_commit_psw
	gset lr, 39
	gget v2, 8
	xor v2, v2, v3
	set sp, $0800
	bmask_clear cpu_commit_psw_done, v2, sp
	clr v2
cpu_swap_register
	ldi8 sp, 32
	add sp, sp, v2
	ggetr v4, v2
	ggetr lr, sp
	gsetr v4, sp
	gsetr lr, v2
	inc v2
	bne cpu_swap_register, v2, 6
cpu_commit_psw_done
	gset v3, 8
	gget lr, 39
	rts

cpu_error_register
	bmask_set cpu_address_error, lr, 4
	gget v2, 23
	bmask_clear cpu_error_read, lr, 1
	seth v2, 0		; any byte/word write clears all CPUERR bits
	gset v2, 23
cpu_error_read
	shr v2, v2, 8
cpu_read_value
	bmask_clear cpu_read_word, lr, 2
	bmask_clear cpu_read_low, v4, 1
	shr v2, v2, 8
cpu_read_low
	seth v2, 0
cpu_read_word
	mov v4, v2
	b memory_return

; Merge the highest PIR level with the already selected UART/LTC/external
; request. PIR wins equal BR levels, except the dedicated EVENT/LTC input.
; Preserve v0, v1 and lr (peripherals_poll's calling convention).
cpu_interrupt_select
	gget sp, 21
	shr sp, sp, 9
	clr v3
cpu_interrupt_scan
	cbz sp, cpu_interrupt_found
	shr sp, sp, 1
	inc v3
	b cpu_interrupt_scan
cpu_interrupt_found
	cbz v3, cpu_interrupt_done
	shr v4, v2, 8
	and v4, v4, 7
	bltu cpu_interrupt_done, v3, v4
	bne cpu_interrupt_use, v3, v4
	set sp, $8e40
	beq cpu_interrupt_done, v2, sp
cpu_interrupt_use
	shl v2, v3, 8
	set sp, $88a0
	or v2, v2, sp		; vector 240, software IRQ tag, selected PIR level
cpu_interrupt_done
	rts

cpu_bus_error
	set v2, $2000		; CPUERR.NXM: nonexistent memory below the I/O page
	set sp, $e000
	bltu cpu_error_trap, v4, sp
	set v2, $1000		; CPUERR.TMO: nonexistent I/O device
	b cpu_error_trap
cpu_address_error
	set v2, $4000		; CPUERR.ADR: odd word / internal-register fetch
	b cpu_error_trap
cpu_illegal_halt
	set v2, $8000		; CPUERR.HALT: HALT outside kernel mode
cpu_error_trap
	gget v3, 23
	or v3, v3, v2
	gset v3, 23
	gget v2, 14
	bmask_set cpu_red_stack, v2, 4
	clr v2
	gset v2, 14		; aborted instructions do not generate TRACE
	ldi8 v2, 1
	gset v2, 10
	ldi8 sp, 4
	far_jump trap_entry

; A RED error is an abort while pushing a trap/interrupt frame, NOT a second
; numerical stack boundary. Restart with SP=4 and the original PC/PSW.
cpu_red_stack
	ldi8 v3, $20
	bmask_set cpu_double_abort, v2, v3
	gget v3, 23
	set v2, $0400
	or v3, v3, v2
	gset v3, 23
	ldi8 v2, $26		; recovery + vector push + yellow recursion inhibit
	gset v2, 14
	gget v3, 8
	shr lr, v3, 14
	bne cpu_red_mode_ready, lr, 2
	clr lr
cpu_red_mode_ready
	ldi8 sp, 4
	ldi8 v4, 4
	; Keep lr=old CM: the ordinary far_jump macro would overwrite it.
	set v2, trap_entry_stack_ready
	mov pc, v2
cpu_double_abort
	ldi8 v2, 4		; emergency memory unavailable; stop until console exists
	gset v2, 10
cpu_double_abort_stopped
	ifdef J11_BOOT_TRACE
	call boot_trace_stop_tick
	endif
	b cpu_double_abort_stopped

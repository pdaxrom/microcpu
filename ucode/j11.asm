	include ../asm/include/pseudo.inc

	org $0000

reset_entry
	b fetch

; Fixed microengine ABI entry: rtl/j11_microengine.v redirects failed guest
; transactions to byte address 0002.  Trap mechanics remain in microcode.
bus_error_entry
	clr v2
	gset v2, 14		; failed instructions do not produce a trace trap
	set v2, 1
	gset v2, 10
	set sp, 4		; PDP-11 bus/address-error vector 004
	b trap_entry

wait_instruction
	gget v2, 14
	bne trace_entry, v2, 0
	gget v2, 11
	bge wait_instruction, v2, 0

fetch
	gget v2, 14		; TRACE has priority over device interrupts
	bne trace_entry, v2, 0
	gget v0, 7		; v0 <- guest PC
	gget v2, 11		; take a latched device interrupt at an instruction boundary
	blt interrupt_priority, v2, 0
fetch_instruction
	ldr v1, v0, 0		; v1 <- guest word at PC
	gset v1, 9		; guest IR <- fetched word
	add v0, v0, 2		; PC advances by one PDP-11 word
	gset v0, 7		; guest PC <- PC + 2
	gget v2, 8		; remember T from before instruction execution
	set v3, $10
	and v2, v2, v3
	gset v2, 14
	b decode

interrupt_priority
	mov v3, v2
	shr v3, v3, 8
	and v3, v3, 7		; pending BR level
	gget v4, 8
	shr v4, v4, 5
	and v4, v4, 7		; current PSW priority
	ble fetch_instruction, v3, v4
	b interrupt_entry

decode
	beq halt, v1, 0		; 000000: HALT
	beq wait_instruction, v1, 1	; 000001: WAIT
	beq return_interrupt, v1, 2	; 000002: RTI
	beq breakpoint_trap, v1, 3	; 000003: BPT
	beq io_trap, v1, 4		; 000004: IOT
	beq reset_instruction, v1, 5	; 000005: RESET
	beq return_from_trace, v1, 6	; 000006: RTT
	beq move_from_processor_type, v1, 7	; 000007: MFPT
	mov v2, v1
	shr v2, v2, 8
	beq decode_zero, v2, 0
	bltu branch_low, v2, 8	; 0004xx..0034xx: BR and low branch group
	setl v3, $88
	beq emt_trap, v2, v3	; 1040xx: EMT
	inc v3
	beq trap_trap, v2, v3	; 1044xx: TRAP

	mov v3, v1
	shr v3, v3, 12
	beq move, v3, 1		; 01SSDD: MOV
	beq double_operand, v3, 2	; 02SSDD: CMP
	beq double_operand, v3, 3	; 03SSDD: BIT
	beq double_operand, v3, 4	; 04SSDD: BIC
	beq double_operand, v3, 5	; 05SSDD: BIS
	beq double_operand, v3, 6	; 06SSDD: ADD
	beq move, v3, 9		; 11SSDD: MOVB
	beq double_operand, v3, 10	; 12SSDD: CMPB
	beq double_operand, v3, 11	; 13SSDD: BITB
	beq double_operand, v3, 12	; 14SSDD: BICB
	beq double_operand, v3, 13	; 15SSDD: BISB
	beq double_sub_operand, v3, 14	; 16SSDD: SUB

	mov v3, v1
	shr v3, v3, 9
	beq jump_subroutine, v3, 4	; 004RDD: JSR
	set sp, $38
	beq multiply, v3, sp		; 070RSS: MUL
	set sp, $3f
	beq subtract_one_branch, v3, sp	; 077RNN: SOB
	sub sp, sp, 3
	beq exclusive_or, v3, sp	; 074RDD: XOR

	setl sp, $80
	bltu decode_single_operand, v2, sp
	setl sp, $88
	bltu branch_high, v2, sp	; 1000xx..1034xx: high branch group

decode_single_operand
	; Single-operand word/byte opcodes share bits 14:6.
	mov v3, v1
	shl v3, v3, 1
	shr v3, v3, 7
	setl v2, $28
	beq clear_operand, v3, v2	; 0050DD/1050DD: CLR/CLRB
	setl v2, $29
	beq complement_operand, v3, v2	; 0051DD/1051DD: COM/COMB
	setl v2, $2a
	beq increment_operand, v3, v2	; 0052DD/1052DD: INC/INCB
	setl v2, $2b
	beq decrement_operand, v3, v2	; 0053DD/1053DD: DEC/DECB
	setl v2, $2c
	beq negative_operand, v3, v2	; 0054DD/1054DD: NEG/NEGB
	setl v2, $2d
	beq add_carry_operand, v3, v2	; 0055DD/1055DD: ADC/ADCB
	setl v2, $2e
	beq subtract_carry_operand, v3, v2	; 0056DD/1056DD: SBC/SBCB
	setl v2, $2f
	beq test_operand, v3, v2	; 0057DD/1057DD: TST/TSTB
	setl v2, $30
	beq rotate_right_operand, v3, v2	; 0060DD/1060DD: ROR/RORB
	setl v2, $31
	beq rotate_left_operand, v3, v2	; 0061DD/1061DD: ROL/ROLB
	setl v2, $32
	beq arithmetic_shift_right_operand, v3, v2	; 0062DD/1062DD: ASR/ASRB
	setl v2, $33
	beq arithmetic_shift_left_operand, v3, v2	; 0063DD/1063DD: ASL/ASLB
	inc v2
	beq move_to_processor_status, v3, v2	; 1064SS: MTPS (0064NN is MARK)
	setl v2, $37
	beq sign_extend_operand, v3, v2	; 0067DD: SXT
	b reserved_instruction

decode_zero
	mov v2, v1
	shr v2, v2, 3
	set v3, $10
	beq return_subroutine, v2, v3	; 00020R: RTS
	add v3, v3, 3
	beq set_priority, v2, v3	; 00023N: SPL
	mov v2, v1
	shr v2, v2, 6
	beq jump, v2, 1	; 0001DD: JMP
	beq swap_bytes_operand, v2, 3	; 0003DD: SWAB
	mov v2, v1
	shr v2, v2, 4
	beq condition_clear, v2, 10	; 000240..000257
	beq condition_set, v2, 11	; 000260..000277
	b reserved_instruction

; Every conditional branch is encoded as an adjacent even/odd pair.  Keep the
; shared evaluator next to the decoder so its relative branches remain in range
; as the production uROM grows beyond 1024 words.
branch_low
	and lr, v2, 1		; required predicate value
	shr v2, v2, 1		; 0=BR, 1=Z, 2=N xor V, 3=Z or (N xor V)
	beq branch_taken, v2, 0
	gget v3, 8
	beq branch_low_zero, v2, 1
	mov v4, v3
	shr v4, v4, 2
	xor v4, v4, v3
	and v4, v4, 2
	beq branch_low_signed, v2, 2
	and v3, v3, 4
	or v4, v4, v3
	b branch_boolean

branch_low_zero
	shr v4, v3, 2
	and v4, v4, 1
	b branch_compare

branch_low_signed
	shr v4, v4, 1
	b branch_compare

branch_high
	and lr, v2, 1		; required predicate value
	and v2, v2, 6		; 0=N, 2=C or Z, 4=V, 6=C
	gget v3, 8
	beq branch_high_carry_zero, v2, 2
	shr v2, v2, 1
	xor v2, v2, 3		; N/V/C selectors become shifts 3/1/0
	shr v4, v3, v2
	and v4, v4, 1
	b branch_compare

branch_high_carry_zero
	and v4, v3, 5
	b branch_boolean

branch_compare
	beq branch_taken, v4, lr
	b fetch

branch_boolean
	beq branch_compare, v4, 0
	setl v4, 1
	b branch_compare

branch_taken
	sxt v1, v1		; sign extend IR low byte
	shl v1, v1, 1		; PDP-11 branch displacement is in words
	add v0, v0, v1		; v0 still contains post-fetch guest PC
	gset v0, 7
	b fetch

condition_clear
	gget v3, 8
	and v1, v1, 15
	inv v1, v1
	and v3, v3, v1
	gset v3, 8
	b fetch

condition_set
	gget v3, 8
	and v1, v1, 15
	or v3, v3, v1
	gset v3, 8
	b fetch

move_from_processor_type
	sub v2, v1, 2		; DCJ11 MFPT result is 5
	gset v2, 0
	b fetch

set_priority
	and v1, v1, 7
	shl v1, v1, 5
	gget v3, 8
	set sp, $ff1f		; replace PSW priority, preserve all other bits
	and v3, v3, sp
	or v3, v3, v1
	gset v3, 8
	b fetch

reset_instruction
	gget v2, 8
	set v3, $c000
	and v2, v2, v3
	bne fetch, v2, 0	; user/supervisor RESET is a NOP on DCJ11
	set v2, 1
	gset v2, 15		; pulse the board peripheral-reset control
	b fetch

multiply
	; Snapshot R before resolving the source EA.  DCJ11 EIS instructions use
	; the pre-EA register value even when the source modifies that register.
	mov v2, v1
	shr v2, v2, 6
	and v2, v2, 7
	gset v2, 12		; destination register number
	ggetr v3, v2
	gset v3, 13		; signed register operand

	mov v2, v1
	set sp, $3f
	and v2, v2, sp
	bsr ea_resolve
	beq multiply_source_register, v2, 0
	ldr v4, v4, 0
	b multiply_operands_ready

multiply_source_register
	ggetr v4, v4

multiply_operands_ready
	gget v3, 13
	clr v0			; result sign: sign(R) xor sign(source)
	bge multiply_register_magnitude_ready, v3, 0
	clr sp
	sub v3, sp, v3
	xor v0, v0, 1

multiply_register_magnitude_ready
	bge multiply_source_magnitude_ready, v4, 0
	clr sp
	sub v4, sp, v4
	xor v0, v0, 1

multiply_source_magnitude_ready
	; Unsigned 16x16 shift-add. v4:sp is the 32-bit accumulator,
	; v3 is the multiplicand, and v2 carries the 17th add bit.
	mov sp, v4
	clr v4
	set lr, 16

multiply_loop
	clr v2
	and v1, sp, 1
	beq multiply_shift, v1, 0
	add v4, v4, v3
	getf v2
	and v2, v2, 1

multiply_shift
	and v1, v4, 1
	shr sp, sp, 1
	beq multiply_shift_high, v1, 0
	set v1, $8000
	or sp, sp, v1

multiply_shift_high
	shr v4, v4, 1
	beq multiply_next_bit, v2, 0
	set v1, $8000
	or v4, v4, v1

multiply_next_bit
	dec lr
	bne multiply_loop, lr, 0

	; Convert the magnitude to a signed 32-bit result when required.
	beq multiply_signed_ready, v0, 0
	inv sp, sp
	add sp, sp, 1
	getf v2
	and v2, v2, 1
	inv v4, v4
	add v4, v4, v2

multiply_signed_ready
	; MUL flags use the full 32-bit product. C reports that the product does
	; not fit in a signed 16-bit word; V is always clear.
	clr v0
	bge multiply_zero, v4, 0
	or v0, v0, 8

multiply_zero
	or v1, v4, sp
	bne multiply_carry, v1, 0
	or v0, v0, 4

multiply_carry
	blt multiply_carry_negative_low, sp, 0
	bne multiply_set_carry, v4, 0
	b multiply_write

multiply_carry_negative_low
	set v1, $ffff
	bne multiply_set_carry, v4, v1
	b multiply_write

multiply_set_carry
	or v0, v0, 1

multiply_write
	gget v2, 12
	gsetr v4, v2		; high product word
	or v2, v2, 1
	gsetr sp, v2		; odd R selects the low word twice, like DCJ11
	gget v1, 8
	set v2, $fff0
	and v1, v1, v2
	or v1, v1, v0
	gset v1, 8
	b fetch

breakpoint_trap
	set sp, $0c		; PDP-11 BPT vector 014
	b software_trap

io_trap
	set sp, $10		; PDP-11 IOT vector 020
	b software_trap

emt_trap
	set sp, $18		; PDP-11 EMT vector 030
	b software_trap

trap_trap
	set sp, $1c		; PDP-11 TRAP vector 034

software_trap
	clr v2
	gset v2, 10
	b trap_entry

subtract_one_branch
	mov v2, v1
	shr v2, v2, 6
	and v2, v2, 7
	ggetr v3, v2
	sub v3, v3, 1
	gsetr v3, v2
	beq fetch, v3, 0
	set sp, $3f
	and v1, v1, sp
	shl v1, v1, 1
	gget v0, 7
	sub v0, v0, v1
	gset v0, 7
	b fetch

jump
	mov v2, v1
	set sp, $3f
	and v2, v2, sp
	mov v3, v2
	shr v3, v3, 3
	beq illegal_jump, v3, 0
	bsr ea_resolve
	gset v4, 7
	b fetch

illegal_jump
	set v2, 2
	gset v2, 10
	set sp, 4		; JMP mode 0 enters vector 004 on DCJ11
	b trap_entry

jump_subroutine
	mov v2, v1
	set sp, $3f
	and v2, v2, sp
	mov v3, v2
	shr v3, v3, 3
	beq reserved_instruction, v3, 0	; JSR mode 0 enters vector 010
	bsr ea_resolve
	mov v2, v1
	shr v2, v2, 6
	and v2, v2, 7		; link register
	gget sp, 6
	sub sp, sp, 2
	gset sp, 6
	; Read the link register after destination EA side effects and after the
	; stack decrement.  The latter preserves DCJ11 JSR SP,dst behavior.
	ggetr v3, v2
	str v3, sp, 0
	gsetr v0, v2		; return PC already includes any EA extension
	gset v4, 7
	b fetch

return_subroutine
	and v2, v1, 7
	ggetr v4, v2		; branch target is the old link register
	gget sp, 6
	ldr v3, sp, 0
	add sp, sp, 2
	gset sp, 6
	gsetr v3, v2
	beq return_subroutine_done, v2, 7	; RTS PC keeps the popped PC
	gset v4, 7
return_subroutine_done
	b fetch

move
	mov v2, v1
	shr v2, v2, 6
	set sp, $3f
	and v2, v2, sp
	bsr ea_resolve
	beq move_source_register, v2, 0
	blt move_source_byte_memory, v1, 0
	ldr v3, v4, 0
	b move_destination

move_source_byte_memory
	ldrl v3, v4, 0
	sxt v3, v3
	b move_destination

move_source_register
	; DCJ11 samples a register-direct source after resolving a non-register
	; destination, so destination autoincrement/decrement is already visible.
	gset v4, 12
	mov v2, v1
	set sp, $3f
	and v2, v2, sp
	bsr ea_resolve
	gget sp, 12
	ggetr v3, sp
	bge move_register_source_ready, v1, 0
	sxt v3, v3
move_register_source_ready
	b move_destination_resolved

move_destination
	mov v2, v1
	set sp, $3f
	and v2, v2, sp
	bsr ea_resolve
move_destination_resolved
	beq move_destination_register, v2, 0
	blt move_destination_byte_memory, v1, 0
	str v3, v4, 0
	b move_flags

move_destination_byte_memory
	strl v3, v4, 0
	b move_flags

move_destination_register
	gsetr v3, v4
	b move_flags

double_sub_operand
	; ea_resolve treats the sign of this working IR copy as the byte-width flag.
	; SUB has bit 15 set but is word-only, so clear that bit here. The original
	; opcode remains intact in guest context word 9 for operation dispatch.
	shl v1, v1, 1
	shr v1, v1, 1
	b double_operand

exclusive_or
	; Present XOR's register operand as a mode-0 source to the common
	; double-operand resolver.  The unmodified opcode remains in guest IR.
	shl v1, v1, 7
	shr v1, v1, 7
	b double_operand

double_operand
	mov v2, v1
	shr v2, v2, 6
	set sp, $3f
	and v2, v2, sp
	bsr ea_resolve
	beq double_source_register, v2, 0
	blt double_source_byte_memory, v1, 0
	ldr v3, v4, 0
	b double_destination

double_source_byte_memory
	ldrl v3, v4, 0
	seth v3, 0
	b double_destination

double_source_register
	; Apply the same DCJ11 late register-source sampling to every resident
	; double-operand instruction, not just MOV/MOVB.
	gset v4, 12
	mov v2, v1
	set sp, $3f
	and v2, v2, sp
	bsr ea_resolve
	gget sp, 12
	ggetr v3, sp
	bge double_register_source_ready, v1, 0
	seth v3, 0
double_register_source_ready
	b double_destination_resolved

double_destination
	mov v2, v1
	set sp, $3f
	and v2, v2, sp
	bsr ea_resolve
double_destination_resolved
	beq double_destination_register, v2, 0
	blt double_destination_byte_memory, v1, 0
	ldr sp, v4, 0
	b double_execute

double_destination_byte_memory
	ldrl sp, v4, 0
	seth sp, 0
	b double_execute

double_destination_register
	ggetr sp, v4

double_execute
	gget lr, 9
	shr lr, lr, 12
	beq double_sub, lr, 14
	and lr, lr, 7
	beq double_compare, lr, 2
	beq double_bit, lr, 3
	beq double_bic, lr, 4
	beq double_bis, lr, 5
	beq double_exclusive_or, lr, 7
	add sp, sp, v3
	b double_write_result

double_sub
	sub sp, sp, v3

double_write_result
	beq double_add_register, v2, 0
	str sp, v4, 0
	b double_arithmetic_flags

double_add_register
	gsetr sp, v4
	b double_arithmetic_flags

double_bic
	inv v3, v3
	and sp, sp, v3
	b double_logic_write

double_bis
	or sp, sp, v3
	b double_logic_write

double_exclusive_or
	xor sp, sp, v3

double_logic_write
	bge double_logic_write_word, v1, 0
	beq double_logic_write_byte_register, v2, 0
	strl sp, v4, 0
	b double_logic_flags_byte

double_logic_write_byte_register
	gsetr sp, v4		; sp still contains the destination's preserved high byte

double_logic_flags_byte
	sxt v3, sp
	b move_flags

double_logic_write_word
	beq double_logic_write_word_register, v2, 0
	str sp, v4, 0
	b double_logic_flags_word

double_logic_write_word_register
	gsetr sp, v4

double_logic_flags_word
	mov v3, sp
	b move_flags

double_compare
	blt double_compare_byte, v1, 0
	sub lr, v3, sp		; PDP-11 CMP computes source - destination
	b double_arithmetic_flags

double_compare_byte
	subb lr, v3, sp
	b double_arithmetic_flags

double_bit
	and lr, sp, v3
	bge double_bit_flags, v1, 0
	sxt lr, lr
double_bit_flags
	mov v3, lr
	b move_flags		; BIT clears V and preserves C like MOV

double_arithmetic_flags
	getf v2
	gget v4, 8
	set sp, $fff0
	and v4, v4, sp
	or v4, v4, v2
	gset v4, 8
	b fetch

clear_operand
	clr v3
	mov v2, v1
	set sp, $3f
	and v2, v2, sp
	bsr ea_resolve
	beq clear_register, v2, 0
	blt clear_byte_memory, v1, 0
	str v3, v4, 0
	b clear_flags

clear_byte_memory
	strl v3, v4, 0
	b clear_flags

clear_register
	bge clear_register_word, v1, 0
	ggetr sp, v4
	setl sp, 0
	gsetr sp, v4
	b clear_flags

clear_register_word
	gsetr v3, v4

clear_flags
	gget v4, 8
	set v2, $fff0		; CLR: N=0, Z=1, V=0, C=0
	and v4, v4, v2
	or v4, v4, 4
	gset v4, 8
	b fetch

fetch_far
	b fetch			; relay for tail handlers beyond direct branch range

; Keep the common control-flow handlers near the center of the image.  The
; microengine branch encoding has a +/-2047-byte range, so this placement stays
; reachable from both the fixed ABI entries and the growing instruction tail.
trace_entry
	clr v2
	gset v2, 14
	gset v2, 10
	gget v0, 7
	set sp, $0c		; PDP-11 trace/BPT vector 014
	b trap_entry

reserved_instruction
	set v2, 2
	gset v2, 10		; cause 2: reserved instruction
	set sp, 8		; PDP-11 reserved-instruction vector 010
	b trap_entry

; Enter a PDP-11 vector.  sp holds the vector address and v0 is the PC after
; the trapping instruction.  The stack frame has old PC at (SP) and old PSW at
; 2(SP), ready for RTI or RTT.
trap_entry
	gget v4, 6
	gget v3, 8
	sub v4, v4, 2
	str v3, v4, 0
	sub v4, v4, 2
	str v0, v4, 0
	gset v4, 6
	ldr v0, sp, 0
	gset v0, 7
	ldr v3, sp, 2
	gset v3, 8
	b fetch

return_interrupt
	set lr, $10		; RTI traces immediately when the restored T bit is set
	b return_common

return_from_trace
	clr lr			; RTT suppresses its own trace boundary

return_common
	gget v4, 6
	ldr v0, v4, 0
	add v4, v4, 2
	ldr v3, v4, 0
	add v4, v4, 2
	gset v4, 6
	gset v0, 7
	gset v3, 8
	and v3, v3, lr
	gset v3, 14
	clr v2
	gset v2, 10
	b fetch

interrupt_entry
	mov sp, v2
	set v3, $ff
	and sp, sp, v3		; pending word low byte is the PDP-11 vector
	clr v3
	gset v3, 11
	b trap_entry

halt
	set v2, 3
	gset v2, 10		; cause 3: HALT until console mode exists

stopped
	b stopped

complement_operand
	mov v2, v1
	set sp, $3f
	and v2, v2, sp
	bsr ea_resolve
	beq complement_register, v2, 0
	blt complement_byte_memory, v1, 0
	ldr sp, v4, 0
	inv v3, sp
	str v3, v4, 0
	b complement_flags

complement_byte_memory
	ldrl sp, v4, 0
	inv v3, sp
	strl v3, v4, 0
	sxt v3, v3
	b complement_flags

complement_register
	ggetr sp, v4
	inv v3, sp
	bge complement_register_word, v1, 0
	seth v3, 0
	setl sp, 0		; retain the destination register's high byte
	or v3, v3, sp
	gsetr v3, v4
	sxt v3, v3
	b complement_flags

complement_register_word
	gsetr v3, v4

complement_flags
	gget v4, 8
	or v4, v4, 1		; COM: C=1; move_flags clears V and sets N/Z
	gset v4, 8
	b move_flags

increment_operand
	set v3, 0		; operation selector: zero means increment
	b adjust_operand

decrement_operand
	set v3, 1
	b adjust_operand

negative_operand
	set v3, 2
	b adjust_operand

add_carry_operand
	set v3, 3
	b adjust_operand

subtract_carry_operand
	set v3, 4
	b adjust_operand

rotate_right_operand
	set v3, 5
	b adjust_operand

rotate_left_operand
	set v3, 6
	b adjust_operand

arithmetic_shift_right_operand
	set v3, 7
	b adjust_operand

arithmetic_shift_left_operand
	set v3, 8

; Arithmetic single-operand instructions and their byte forms share one
; EA/read/modify/write implementation. Context words 12 and 13 retain the
; operation selector and resolved mode; they are internal scratch state.
adjust_operand
	gset v3, 12
	mov v2, v1
	set sp, $3f
	and v2, v2, sp
	bsr ea_resolve
	gset v2, 13		; zero means register, nonzero means memory
	gget v3, 12		; restore the operation selector
	gset v3, 12
	beq adjust_register_load, v2, 0
	blt adjust_byte_memory_load, v1, 0
	ldr sp, v4, 0
	b adjust_word_value

adjust_byte_memory_load
	ldrl sp, v4, 0
	seth sp, 0
	b adjust_byte_value

adjust_register_load
	ggetr sp, v4
	blt adjust_byte_value, v1, 0

adjust_word_value
	mov v3, sp
	gget v2, 12
	beq adjust_word_increment, v2, 0
	beq adjust_word_decrement, v2, 1
	beq adjust_word_negative, v2, 2
	beq adjust_word_add_carry, v2, 3
	beq adjust_word_subtract_carry, v2, 4
	beq adjust_word_rotate_right, v2, 5
	beq adjust_word_rotate_left, v2, 6
	beq adjust_word_shift_right, v2, 7
	beq adjust_word_shift_left, v2, 8
	b adjust_word_test

adjust_word_increment
	add v3, v3, 1
	b adjust_word_preserve_carry

adjust_word_decrement
	sub v3, v3, 1

adjust_word_preserve_carry
	getf lr
	and lr, lr, 14		; INC/DEC replace N/Z/V but preserve old C
	clr v1			; flag merge policy: retain old C
	b adjust_word_write

adjust_word_negative
	clr v3
	sub v3, v3, sp
	b adjust_word_replace_flags

adjust_word_add_carry
	gget lr, 8
	and lr, lr, 1
	beq adjust_word_without_carry, lr, 0
	add v3, v3, 1
	b adjust_word_replace_flags

adjust_word_subtract_carry
	gget lr, 8
	and lr, lr, 1
	beq adjust_word_without_carry, lr, 0
	sub v3, v3, 1
	b adjust_word_replace_flags

adjust_word_without_carry
	add v3, sp, 0		; unchanged result with fresh N/Z and clear V/C

adjust_word_replace_flags
	getf lr
	set v1, 1		; flag merge policy: replace all NZVC
	b adjust_word_write

adjust_word_rotate_right
	and v2, sp, 1		; outgoing bit 0 becomes C
	gset v2, 12
	shr v3, sp, 1
	gget v2, 8
	and v2, v2, 1		; old C enters bit 15
	shl v2, v2, 15
	or v3, v3, v2
	b adjust_shift_flags

adjust_word_rotate_left
	mov v2, sp
	shr v2, v2, 15		; outgoing bit 15 becomes C
	gset v2, 12
	shl v3, sp, 1
	gget v2, 8
	and v2, v2, 1		; old C enters bit 0
	or v3, v3, v2
	b adjust_shift_flags

adjust_word_shift_right
	and v2, sp, 1
	gset v2, 12
	shr v3, sp, 1
	mov v2, sp
	shr v2, v2, 15		; replicate the old sign bit
	shl v2, v2, 15
	or v3, v3, v2
	b adjust_shift_flags

adjust_word_shift_left
	mov v2, sp
	shr v2, v2, 15
	gset v2, 12
	shl v3, sp, 1
	b adjust_shift_flags

adjust_word_test
	add v2, sp, 0		; latch word-width N/Z and clear V/C
	getf lr
	and lr, lr, 12
	set v1, 1
	b adjust_merge_flags

adjust_word_write
	gget v2, 13
	beq adjust_word_register_write, v2, 0
	str v3, v4, 0
	b adjust_merge_flags

adjust_word_register_write
	gsetr v3, v4
	b adjust_merge_flags

adjust_byte_value
	gget v2, 12
	beq adjust_byte_increment, v2, 0
	beq adjust_byte_decrement, v2, 1
	beq adjust_byte_negative, v2, 2
	beq adjust_byte_add_carry, v2, 3
	beq adjust_byte_subtract_carry, v2, 4
	beq adjust_byte_test, v2, 9
	b adjust_byte_shift

adjust_byte_increment
	set v2, $ff
	subb v3, sp, v2		; low-byte x - ff is x + 1 modulo 256
	b adjust_byte_preserve_carry

adjust_byte_decrement
	subb v3, sp, 1

adjust_byte_preserve_carry
	getf lr
	and lr, lr, 14		; INCB/DECB preserve old C
	clr v1
	b adjust_byte_write

adjust_byte_negative
	clr v3
	subb v3, v3, sp
	b adjust_byte_replace_flags

adjust_byte_add_carry
	gget lr, 8
	and lr, lr, 1
	beq adjust_byte_without_carry, lr, 0
	set v2, $ff
	subb v3, sp, v2
	getf lr
	and lr, lr, 14		; subtraction supplies ADCB N/Z/V
	and v2, lr, 4		; with carry in, ADCB carry out equals Z
	beq adjust_byte_add_carry_ready, v2, 0
	or lr, lr, 1
adjust_byte_add_carry_ready
	set v1, 1
	b adjust_byte_write

adjust_byte_subtract_carry
	gget lr, 8
	and lr, lr, 1
	beq adjust_byte_without_carry, lr, 0
	subb v3, sp, 1
	b adjust_byte_replace_flags

adjust_byte_without_carry
	subb v3, sp, 0		; unchanged result with fresh N/Z and clear V/C

adjust_byte_test
	subb v2, sp, 0		; latch byte-width N/Z and clear V/C
	getf lr
	and lr, lr, 12
	set v1, 1
	b adjust_merge_flags

adjust_byte_replace_flags
	getf lr
	set v1, 1
	b adjust_byte_write

adjust_byte_shift
	mov v3, sp
	seth v3, 0		; shifts operate on the low byte only
	beq adjust_byte_rotate_right, v2, 5
	beq adjust_byte_rotate_left, v2, 6
	beq adjust_byte_shift_right, v2, 7
	b adjust_byte_shift_left

adjust_byte_rotate_right
	and v2, v3, 1
	gset v2, 12
	shr v3, v3, 1
	gget v2, 8
	and v2, v2, 1
	shl v2, v2, 7
	or v3, v3, v2
	b adjust_shift_flags

adjust_byte_rotate_left
	mov v2, v3
	shr v2, v2, 7
	gset v2, 12
	shl v3, v3, 1
	seth v3, 0
	gget v2, 8
	and v2, v2, 1
	or v3, v3, v2
	b adjust_shift_flags

adjust_byte_shift_right
	and v2, v3, 1
	gset v2, 12
	mov lr, v3
	shr lr, lr, 7		; retain the old byte sign
	shr v3, v3, 1
	shl lr, lr, 7
	or v3, v3, lr
	b adjust_shift_flags

adjust_byte_shift_left
	mov v2, v3
	shr v2, v2, 7
	gset v2, 12
	shl v3, v3, 1
	seth v3, 0

; Build NZVC for a shift. The preceding operation stored outgoing C in
; context word 12; overflow is the PDP-11 definition N xor C.
adjust_shift_flags
	blt adjust_shift_byte_nz, v1, 0
	add v2, v3, 0		; latch word-width N/Z
	b adjust_shift_flags_latched

adjust_shift_byte_nz
	subb v2, v3, 0		; latch byte-width N/Z

adjust_shift_flags_latched
	getf lr
	and lr, lr, 12		; retain N/Z and rebuild V/C below
	gget v2, 12
	shl v2, v2, 3
	xor v2, v2, lr
	and v2, v2, 8		; bit 3 now holds N xor C
	shr v2, v2, 2		; move it to PSW V
	or lr, lr, v2
	gget v2, 12
	or lr, lr, v2		; outgoing bit becomes PSW C
	blt adjust_shift_finish_byte, v1, 0
	set v1, 1
	b adjust_word_write

adjust_shift_finish_byte
	set v1, 1

adjust_byte_write
	gget v2, 13
	beq adjust_byte_register_write, v2, 0
	strl v3, v4, 0
	b adjust_merge_flags

adjust_byte_register_write
	setl sp, 0		; preserve the destination register's high byte
	or v3, v3, sp
	gsetr v3, v4

adjust_merge_flags
	gget v4, 8
	set sp, $fff0		; retain upper PSW and select carry policy
	bne adjust_merge_mask_ready, v1, 0
	inc sp			; INC/DEC retain old C
adjust_merge_mask_ready
	and v4, v4, sp
	or v4, v4, lr
	gset v4, 8
	b fetch

swap_bytes_operand
	shl v2, v1, 10
	shr v2, v2, 10
	bsr ea_resolve
	beq swap_bytes_register_load, v2, 0
	ldr sp, v4, 0
	b swap_bytes_value

swap_bytes_register_load
	ggetr sp, v4

swap_bytes_value
	mov v3, sp
	shr v3, v3, 8
	shl sp, sp, 8
	or v3, v3, sp
	beq swap_bytes_register_write, v2, 0
	str v3, v4, 0
	b swap_bytes_flags

swap_bytes_register_write
	gsetr v3, v4

swap_bytes_flags
	; SWAB derives N/Z from the result low byte and clears V/C.
	subb v2, v3, 0
	getf lr
	and lr, lr, 12
	set v1, 1
	b adjust_merge_flags

test_operand
	set v3, 9
	b adjust_operand

; Resolve one PDP-11 effective-address specifier.  Input: v2=mode/reg,
; v1=IR (bit 15 selects byte width), v0=cached guest PC.  Output: v2=mode
; (zero means register), v4=register number or memory address.  Addressing side
; effects and extension-word fetches happen here, so all future instructions can
; reuse the same EA implementation without applying them twice.
ea_resolve
	mov v4, v2
	and v4, v4, 7
	shr v2, v2, 3
	beq ea_register, v2, 0
	beq ea_deferred, v2, 1
	beq ea_autoincrement, v2, 2
	beq ea_autoincrement_deferred, v2, 3
	beq ea_autodecrement, v2, 4
	beq ea_autodecrement_deferred, v2, 5
	beq ea_index, v2, 6
	b ea_index_deferred

ea_register
	rts

ea_deferred
	ggetr v4, v4
	rts

ea_autoincrement
	ggetr sp, v4
	bgeu ea_autoincrement_two, v4, 6
	blt ea_autoincrement_one, v1, 0
ea_autoincrement_two
	add sp, sp, 2
	gsetr sp, v4
	bne ea_autoincrement_two_not_pc, v4, 7
	mov v0, sp
ea_autoincrement_two_not_pc
	sub v4, sp, 2
	rts

ea_autoincrement_one
	inc sp
	gsetr sp, v4
	sub v4, sp, 1
	rts

ea_autoincrement_deferred
	ggetr sp, v4
	add sp, sp, 2
	gsetr sp, v4
	bne ea_autoincrement_deferred_not_pc, v4, 7
	mov v0, sp
ea_autoincrement_deferred_not_pc
	sub sp, sp, 2
	ldr v4, sp, 0
	rts

ea_autodecrement
	ggetr sp, v4
	bgeu ea_autodecrement_two, v4, 6
	blt ea_autodecrement_one, v1, 0
ea_autodecrement_two
	sub sp, sp, 2
	gsetr sp, v4
	bne ea_autodecrement_done, v4, 7
	mov v0, sp
ea_autodecrement_done
	mov v4, sp
	rts

ea_autodecrement_one
	dec sp
	gsetr sp, v4
	mov v4, sp
	rts

ea_autodecrement_deferred
	ggetr sp, v4
	sub sp, sp, 2
	gsetr sp, v4
	bne ea_autodecrement_deferred_not_pc, v4, 7
	mov v0, sp
ea_autodecrement_deferred_not_pc
	ldr v4, sp, 0
	rts

ea_index
	ldr sp, v0, 0
	add v0, v0, 2
	gset v0, 7
	ggetr v4, v4
	add v4, v4, sp
	rts

ea_index_deferred
	ldr sp, v0, 0
	add v0, v0, 2
	gset v0, 7
	ggetr v4, v4
	add v4, v4, sp
	ldr v4, v4, 0
	rts

sign_extend_operand
	blt move_from_processor_status, v1, 0	; 1067DD: MFPS
	clr v3
	gget v2, 8
	and v2, v2, 8
	beq sign_extend_resolve, v2, 0
	inv v3, v3

sign_extend_resolve
	shl v2, v1, 10
	shr v2, v2, 10
	bsr ea_resolve
	beq sign_extend_register, v2, 0
	str v3, v4, 0
	b move_flags

sign_extend_register
	gsetr v3, v4
	; Fall through: SXT sets N/Z from the full-word result, clears V,
	; and preserves the old carry through the shared MOV flag path.
	b move_flags

move_from_processor_status
	gget v3, 8
	sxt v3, v3		; MFPS sign-extends a register result
	b move_destination

move_to_processor_status
	bge reserved_instruction, v1, 0	; MARK remains unsupported
	mov v2, v1
	set sp, $3f
	and v2, v2, sp
	bsr ea_resolve
	beq move_to_processor_status_register, v2, 0
	ldrl v3, v4, 0
	b move_to_processor_status_apply

move_to_processor_status_register
	ggetr v3, v4

move_to_processor_status_apply
	seth v3, 0
	setl sp, $ef		; MTPS writes priority and NZVC, but not T
	and v3, v3, sp
	gget v4, 8
	set sp, $ff10		; preserve upper PSW and the old T bit
	and v4, v4, sp
	or v4, v4, v3
	gset v4, 8
	b fetch_far

move_flags
	gget v4, 8
	set v2, $fff1		; clear N, Z, and V; preserve C and upper PSW
	and v4, v4, v2
	beq move_zero, v3, 0
	blt move_negative, v3, 0
	gset v4, 8
	b fetch_far

move_zero
	or v4, v4, 4
	gset v4, 8
	b fetch_far

move_negative
	or v4, v4, 8
	gset v4, 8
	b fetch_far

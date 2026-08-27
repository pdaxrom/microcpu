	cpu dcj-11
	org 0

start
	scc

	; Register MOVB sign-extends into a register.
	mov #012345, r0
	movb r0, r2
	mov r2, result_register

	mov #source_deferred, r1
	movb (r1), r0
	mov r0, result_source_deferred

	; Byte autoincrement/decrement is one for R0..R5 and two for SP/PC.
	mov #source_autoincrement, r1
	movb (r1)+, r0
	mov r0, result_source_autoincrement
	mov r1, result_source_autoincrement_r1

	mov #source_autoincrement_sp, sp
	movb (sp)+, r0
	mov r0, result_source_autoincrement_sp
	mov sp, result_source_autoincrement_sp_value

	mov #pointer_source_autoincrement_deferred, r1
	movb @(r1)+, r0
	mov r0, result_source_autoincrement_deferred
	mov r1, result_source_autoincrement_deferred_r1

	mov #source_autodecrement+1, r1
	movb -(r1), r0
	mov r0, result_source_autodecrement
	mov r1, result_source_autodecrement_r1

	mov #source_autodecrement_sp+2, sp
	movb -(sp), r0
	mov r0, result_source_autodecrement_sp
	mov sp, result_source_autodecrement_sp_value

	mov #pointer_source_autodecrement_deferred+2, r1
	movb @-(r1), r0
	mov r0, result_source_autodecrement_deferred
	mov r1, result_source_autodecrement_deferred_r1

	mov #source_index-3, r1
	movb 3(r1), r0
	mov r0, result_source_index

	mov #pointer_source_index_deferred-5, r1
	movb @5(r1), r0
	mov r0, result_source_index_deferred

	movb @#source_absolute, r0
	mov r0, result_source_absolute

	movb source_pc_relative, r0
	mov r0, result_source_pc_relative

	movb @pointer_source_pc_relative_deferred, r0
	mov r0, result_source_pc_relative_deferred

	; Every memory destination writes only one byte, including odd addresses.
	mov #destination_deferred, r1
	movb #021, (r1)

	mov #destination_autoincrement, r1
	movb #022, (r1)+
	mov r1, result_destination_autoincrement_r1

	mov #destination_autoincrement_sp, sp
	movb #023, (sp)+
	mov sp, result_destination_autoincrement_sp_value

	mov #pointer_destination_autoincrement_deferred, r1
	movb #024, @(r1)+
	mov r1, result_destination_autoincrement_deferred_r1

	mov #destination_autodecrement+1, r1
	movb #025, -(r1)
	mov r1, result_destination_autodecrement_r1

	mov #destination_autodecrement_sp+2, sp
	movb #026, -(sp)
	mov sp, result_destination_autodecrement_sp_value

	mov #pointer_destination_autodecrement_deferred+2, r1
	movb #027, @-(r1)
	mov r1, result_destination_autodecrement_deferred_r1

	mov #destination_index-3, r1
	movb #030, 3(r1)

	mov #pointer_destination_index_deferred-5, r1
	movb #031, @5(r1)

	movb #032, @#destination_absolute
	movb #033, destination_pc_relative
	movb #034, @pointer_destination_pc_relative_deferred

	; Immediate byte occupies a word, sign-extends to R0, and preserves C.
	movb #0200, r0
	halt

code_end
	ds 01000-code_end
result_register
	dw 0
result_source_deferred
	dw 0
result_source_autoincrement
	dw 0
result_source_autoincrement_r1
	dw 0
result_source_autoincrement_sp
	dw 0
result_source_autoincrement_sp_value
	dw 0
result_source_autoincrement_deferred
	dw 0
result_source_autoincrement_deferred_r1
	dw 0
result_source_autodecrement
	dw 0
result_source_autodecrement_r1
	dw 0
result_source_autodecrement_sp
	dw 0
result_source_autodecrement_sp_value
	dw 0
result_source_autodecrement_deferred
	dw 0
result_source_autodecrement_deferred_r1
	dw 0
result_source_index
	dw 0
result_source_index_deferred
	dw 0
result_source_absolute
	dw 0
result_source_pc_relative
	dw 0
result_source_pc_relative_deferred
	dw 0
result_destination_autoincrement_r1
	dw 0
result_destination_autoincrement_sp_value
	dw 0
result_destination_autoincrement_deferred_r1
	dw 0
result_destination_autodecrement_r1
	dw 0
result_destination_autodecrement_sp_value
	dw 0
result_destination_autodecrement_deferred_r1
	dw 0

result_end
	ds 01100-result_end
destination_deferred
	db 0
destination_autoincrement
	db 0
destination_autoincrement_sp
	db 0
destination_autoincrement_deferred
	db 0
destination_autodecrement
	db 0
destination_autodecrement_sp
	db 0
destination_autodecrement_deferred
	db 0
destination_index
	db 0
destination_index_deferred
	db 0
destination_absolute
	db 0
destination_pc_relative
	db 0
destination_pc_relative_deferred
	db 0

destination_end
	ds 01200-destination_end
source_deferred
	db 0201, 0
source_autoincrement
	db 002, 0
source_autoincrement_sp
	db 0203, 0
pointer_source_autoincrement_deferred
	dw source_autoincrement_deferred
source_autoincrement_deferred
	db 004, 0
source_autodecrement
	db 0205, 0
source_autodecrement_sp
	db 006, 0
pointer_source_autodecrement_deferred
	dw source_autodecrement_deferred
source_autodecrement_deferred
	db 0207, 0
source_index
	db 010, 0
pointer_source_index_deferred
	dw source_index_deferred
source_index_deferred
	db 0211, 0
source_absolute
	db 012, 0
source_pc_relative
	db 0213, 0
pointer_source_pc_relative_deferred
	dw source_pc_relative_deferred
source_pc_relative_deferred
	db 014, 0
pointer_destination_autoincrement_deferred
	dw destination_autoincrement_deferred
pointer_destination_autodecrement_deferred
	dw destination_autodecrement_deferred
pointer_destination_index_deferred
	dw destination_index_deferred
pointer_destination_pc_relative_deferred
	dw destination_pc_relative_deferred

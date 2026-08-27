	cpu dcj-11
	org 0

start
	scc

	; Source modes 2..7.  Modes 0 and 1 have dedicated smoke tests too.
	mov #source_autoincrement, r1
	mov (r1)+, r0
	mov r0, result_source_autoincrement
	mov r1, result_source_autoincrement_r1

	mov #pointer_source_autoincrement_deferred, r1
	mov @(r1)+, r0
	mov r0, result_source_autoincrement_deferred
	mov r1, result_source_autoincrement_deferred_r1

	mov #source_autodecrement+2, r1
	mov -(r1), r0
	mov r0, result_source_autodecrement
	mov r1, result_source_autodecrement_r1

	mov #pointer_source_autodecrement_deferred+2, r1
	mov @-(r1), r0
	mov r0, result_source_autodecrement_deferred
	mov r1, result_source_autodecrement_deferred_r1

	mov #source_index-4, r1
	mov 4(r1), r0
	mov r0, result_source_index

	mov #pointer_source_index_deferred-6, r1
	mov @6(r1), r0
	mov r0, result_source_index_deferred

	mov @#source_absolute, r0
	mov r0, result_source_absolute

	mov source_pc_relative, r0
	mov r0, result_source_pc_relative

	mov @pointer_source_pc_relative_deferred, r0
	mov r0, result_source_pc_relative_deferred

	; Destination modes 1..7, including their normal PC forms.
	mov #destination_deferred, r1
	mov #010101, (r1)

	mov #destination_autoincrement, r1
	mov #020202, (r1)+
	mov r1, result_destination_autoincrement_r1

	mov #pointer_destination_autoincrement_deferred, r1
	mov #030303, @(r1)+
	mov r1, result_destination_autoincrement_deferred_r1

	mov #destination_autodecrement+2, r1
	mov #040404, -(r1)
	mov r1, result_destination_autodecrement_r1

	mov #pointer_destination_autodecrement_deferred+2, r1
	mov #050505, @-(r1)
	mov r1, result_destination_autodecrement_deferred_r1

	mov #destination_index-4, r1
	mov #060606, 4(r1)

	mov #pointer_destination_index_deferred-6, r1
	mov #070707, @6(r1)

	mov #011011, @#destination_absolute
	mov #022022, destination_pc_relative
	mov #033033, @pointer_destination_pc_relative_deferred

	; MOV clears N/Z/V, preserves C.  Leave an unmistakable final result.
	mov #0100000, r0
	halt

code_end
	ds 01000-code_end
result_source_autoincrement
	dw 0
result_source_autoincrement_r1
	dw 0
result_source_autoincrement_deferred
	dw 0
result_source_autoincrement_deferred_r1
	dw 0
result_source_autodecrement
	dw 0
result_source_autodecrement_r1
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
destination_deferred
	dw 0
destination_autoincrement
	dw 0
result_destination_autoincrement_r1
	dw 0
destination_autoincrement_deferred
	dw 0
result_destination_autoincrement_deferred_r1
	dw 0
destination_autodecrement
	dw 0
result_destination_autodecrement_r1
	dw 0
destination_autodecrement_deferred
	dw 0
result_destination_autodecrement_deferred_r1
	dw 0
destination_index
	dw 0
destination_index_deferred
	dw 0
destination_absolute
	dw 0
destination_pc_relative
	dw 0
destination_pc_relative_deferred
	dw 0

result_end
	ds 01200-result_end
source_autoincrement
	dw 011111
pointer_source_autoincrement_deferred
	dw source_autoincrement_deferred
source_autoincrement_deferred
	dw 022222
source_autodecrement
	dw 033333
pointer_source_autodecrement_deferred
	dw source_autodecrement_deferred
source_autodecrement_deferred
	dw 044444
source_index
	dw 055555
pointer_source_index_deferred
	dw source_index_deferred
source_index_deferred
	dw 066666
source_absolute
	dw 077777
source_pc_relative
	dw 012345
pointer_source_pc_relative_deferred
	dw source_pc_relative_deferred
source_pc_relative_deferred
	dw 076543
pointer_destination_autoincrement_deferred
	dw destination_autoincrement_deferred
pointer_destination_autodecrement_deferred
	dw destination_autodecrement_deferred
pointer_destination_index_deferred
	dw destination_index_deferred
pointer_destination_pc_relative_deferred
	dw destination_pc_relative_deferred

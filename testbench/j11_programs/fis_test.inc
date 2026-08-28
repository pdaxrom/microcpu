; Shared guest harness for handwritten smoke vectors and the exact-reference
; corpus. The including assembly file supplies table/end_table below.
; Row: routine, B-high, B-low, A-high, A-low, answer-high, answer-low, PSW,
;      exception (0/1).  Operands are DEC F-format, high word first.
	cpu dcj-11
	macro check
	cmp #1, #2
	beq *+6
	jmp @#failed
	endm
	org 0
	jmp @#start
	org 4
	dw failed
	dw 0340
	org 010
	dw failed
	dw 0340
	org 0244
	dw arithmetic_error
	dw 0340
	org 01000
start
	mov #010000, sp
	mov #table, r1
	clr r5
next_case
	inc r5
	mov (r1)+, r2
	mov #operands, r0
	mov (r1), (r0)
	mov 2(r1), 2(r0)
	mov 4(r1), 4(r0)
	mov 6(r1), 6(r0)
	clr @#trapped
	mov #0357, @#0177776
	jsr r4, (r2)
	check 014(r1), r3
	check 016(r1), @#trapped
	check (r1), @#operands
	check 2(r1), @#operands+2
	check 010(r1), @#operands+4
	check 012(r1), @#operands+6
	tst @#trapped
	bne error_pointer
	check #operands+4, r0
	br checked_pointer
error_pointer
	check #operands, r0
checked_pointer
	check #010000, sp
	add #020, r1
	cmp #end_table, r1
	bne next_case
	mov #012345, r0
	halt
do_add
	fadd r0
	br get_flags
do_sub
	fsub r0
	br get_flags
do_mul
	fmul r0
	br get_flags
do_div
	fdiv r0
get_flags
	mov @#0177776, r3
	rts r4
arithmetic_error
	; A normal mode-aware trap frame, preserving IPL and the error NZVC.
	add #2, r2
	check r2, (sp)
	check 014(r1), 2(sp)
	inc @#trapped
	rti
failed
	halt
	org 02000
operands
	dw 0, 0, 0, 0
trapped
	dw 0
	org 020000

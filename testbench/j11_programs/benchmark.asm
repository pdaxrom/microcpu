; Identical guest work for old/new engines; no host wall-clock timing.
; The fast deterministic bus isolates microcode cost, not physical FRAM speed.
	cpu dcj-11
	org 0
	mov #04000, sp
	mov #0100, r5
	clr r1
loop
	mov #06000, r2
	mov r1, (r2)+
	movb r1, (r2)
	mov -(r2), r3
	add r3, r1
	jsr pc, bench_step
	sob r5, loop
	cmp #0177777, r1
	bne fail
	mov #012345, r0
	halt
bench_step
	inc r1
	rts pc
fail
	mov #1, r0
	halt

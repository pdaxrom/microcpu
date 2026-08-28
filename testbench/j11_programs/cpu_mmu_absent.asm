; RT-11 probes MMU presence via vector 4, NOT by MMR0.EN readback.
; Exercise every absent MMU register, both byte lanes, reads and writes.
	cpu dcj-11
	macro check
	cmp #1, #2
	beq *+6
	jmp @#failed
	endm
	org 0
	jmp @#start
	org 4
	dw bus_fault, 0340
	org 01000
start
	mov #010000, sp
	spl 7
	clr r4
	mov #1, r5
	mov #0172200, r1
	mov #0100, r2
sk_mmu
	jsr pc, probe
	add #2, r1
	sob r2, sk_mmu
	mov #0177600, r1
	mov #040, r2
u_mmu
	jsr pc, probe
	add #2, r1
	sob r2, u_mmu
	mov #0172516, r1
	jsr pc, probe
	mov #0177572, r1
	jsr pc, probe
	mov #0177574, r1
	jsr pc, probe
	mov #0177576, r1
	jsr pc, probe
	check #01130, r4             ; (64 + 32 + 4) * 6 = 600 faults
	check #020, @#0177766        ; TMO, not ADR/RED/NXM
	clrb @#0177766
	check #0, @#0177766
	mov #012345, r0
	halt
probe
	mov (r1), r0
	mov r0, (r1)
	movb (r1), r0
	movb r0, (r1)
	movb 1(r1), r0
	movb r0, 1(r1)
	rts pc
bus_fault
	inc r4                      ; saved PC already points beyond the access
	rti
failed
	halt

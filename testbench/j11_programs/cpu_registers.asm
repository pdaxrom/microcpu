	cpu dcj-11
	macro check
	cmp #1, #2
	beq *+6
	jmp @#failed
	endm
	org 0
	jmp @#start
	org 4
	dw bus_fault
	dw 0340
	org 01000
start
	mov #010000, sp
	mov #1, r5
	spl 7
	check #0, @#0177744
	check #0, @#0177746
	check #0, @#0177750
	check #0, @#0177752
	check #0, @#0177766
	check #0, @#0177772
	mov #0177777, @#0177744
	mov #0177777, @#0177750
	movb #0377, @#0177751
	mov #0177777, @#0177752
	movb #0377, @#0177753
	check #0, @#0177744
	check #0, @#0177750
	check #0, @#0177752

	; CCR implemented bits are 10:0 except bit 8; RESET leaves them alone.
	mov #2, r5
	mov #0177777, @#0177746
	check #03377, @#0177746
	movb @#0177746, r0
	check #0177777, r0
	movb @#0177747, r0
	check #6, r0
	movb #0125, @#0177746
	check #03125, @#0177746
	movb #1, @#0177747
	check #0125, @#0177746
	movb #0377, @#0177747
	check #03125, @#0177746
	reset
	check #03125, @#0177746

	; Disabled-MMU stubs never become guest RAM or enable translation.
	mov #3, r5
	mov #0172200, r1
	mov #0100, r2
sk_mmu
	mov #0177777, (r1)
	check #0, (r1)+
	sob r2, sk_mmu
	mov #0177600, r1
	mov #040, r2
u_mmu
	movb #0377, 1(r1)
	check #0, (r1)+
	sob r2, u_mmu
	mov #0177777, @#0172516
	mov #0177777, @#0177572
	mov #0177777, @#0177574
	mov #0177777, @#0177576
	check #0, @#0172516
	check #0, @#0177572
	check #0, @#0177574
	check #0, @#0177576

	mov #4, r5
	mov #0177777, @#0177772
	check #0177356, @#0177772
	movb @#0177772, r0
	check #0177756, r0
	movb @#0177773, r0
	check #0177776, r0
	clrb @#0177772
	check #0177356, @#0177772
	movb #2, @#0177773
	check #01042, @#0177772
	clrb @#0177773
	check #0, @#0177772
	mov #01000, r1
	mov #042, r2
	mov #7, r3
pir_levels
	mov r1, @#0177772
	mov r1, r0
	bis r2, r0
	check r0, @#0177772
	asl r1
	add #042, r2
	sob r3, pir_levels
	; RBUF and PIRQ share private storage, but neither may corrupt the other.
	mov #01000, @#0177772
	mov #4, @#0177564
	movb #0125, @#0177566
receive_with_pirq
	tstb @#0177560
	bpl receive_with_pirq
	check #01042, @#0177772
	movb @#0177562, r0
	check #0125, r0
	check #01042, @#0177772
	reset
	check #0, @#0177772

	; CPUERR is sticky, has two write-clear byte lanes, and survives RESET.
	mov #5, r5
	clr r4
	mov @#01001, r0
	check #0100, @#0177766
	mov @#0177774, r0 ; absent STKLIM => I/O timeout, not a register
	check #0120, @#0177766
	reset
	check #0120, @#0177766
	check #0200, @#0177546 ; CPUERR must not leak into the shared LTC context
	clrb @#0177546
	check #0120, @#0177766
	clrb @#0177767
	check #0, @#0177766
	mov @#01001, r0
	movb #0377, @#0177766
	check #0, @#0177766
	check #3, r4

	; Fetching a CPU register is an address error even when it reads as zero.
	mov #6, r5
	mov #after_fetch, r3
	jmp @#0177746
after_fetch
	check #0100, @#0177766
	check #4, r4
	mov #012345, r0
	halt

bus_fault
	inc r4
	cmp #6, r5
	bne normal_fault
	mov r3, (sp)
normal_fault
	rti
failed
	mov r5, r0
	halt

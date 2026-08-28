	cpu dcj-11
	macro check
	cmp #1, #2
	beq *+6
	jmp @#failed
	endm
	org 0
	jmp @#start
	org 4
	dw failed, 0340
	org 010
	dw failed, 0340
	org 0210
	dw disk_irq, 0340
	org 01000
start
	mov #04000, sp
	clr @#014000
	mov #1, r5
	; Three words from SD LBA 21, completion IRQ at BR5/vector 0210.
	mov #06000, @#0177444
	mov #025, @#0177446
	mov #-3, @#0177442
	mov #0121, @#0177440
	check #0, @#0177442
	check #06006, @#0177444
	check #025, @#0177446
	check #0xB05A, @#06000
	check #0xB05B, @#06002
	check #0xB058, @#06004
	check #1, @#014000
	check #0320, @#0177440
	mov #0, @#0177440
	mov #0300, @#0177440     ; rising IE+RDY requests one IRQ without GO
	check #2, @#014000
	check #0300, @#0177440
	mov #0, @#0177440
	mov #2, r5
	; Partial sector write must preserve the remaining 508 bytes.
	mov #012345, @#06200
	mov #067770, @#06202
	mov #06200, @#0177444
	mov #-2, @#0177442
	mov #023, @#0177440
	check #0, @#0177442
	check #06204, @#0177444
	check #0222, @#0177440
	mov #3, r5
	; Cross head 2/sector 21 -> next cylinder; second sector is partial.
	mov #07000, @#0177444
	mov #01025, @#0177446
	mov #-0401, @#0177442
	mov #021, @#0177440
	check #0, @#0177442
	check #010002, @#0177444
	check #1, @#0177460
	check #0, @#0177446
	check #0xE45A, @#07000
	check #0xE4A5, @#07776
	check #0xE75A, @#010000
	mov #4, r5
	; BAI holds the memory address while WC continues advancing.
	clr @#0177460
	mov #2, @#0177446
	mov #020, @#0177450
	mov #06400, @#0177444
	mov #-2, @#0177442
	mov #021, @#0177440
	check #06400, @#0177444
	check #0, @#0177442
	check #0xA75B, @#06400
	mov #5, r5
	; Byte-lane merge and odd BA masking, without starting a command.
	clr @#0177442
	movb #0377, @#0177443
	movb #0376, @#0177442
	check #-2, @#0177442
	mov #06001, @#0177444
	check #06000, @#0177444
	mov #6, r5
	; NEM after one successful word: keep its BA/WC progress.
	clr @#0177450
	mov #0157776, @#0177444
	mov #021, @#0177440
	check #-1, @#0177442
	check #0160000, @#0177444
	check #04100, @#0177450
	check #2, @#0177454
	mov #7, r5
	; Controller clear, unavailable drive and unsupported function.
	mov #040, @#0177450
	check #0200, @#0177440
	mov #1, @#0177450
	mov #-1, @#0177442
	mov #021, @#0177440
	check #010101, @#0177450 ; selected drive is preserved with NED
	mov #040, @#0177450
	mov #077, @#0177440
	check #1, @#0177454
	mov #010, r5
	; A nonzero BA extension is explicitly NEM in this 56-KiB DMA prototype.
	mov #040, @#0177450
	mov #-1, @#0177442
	mov #0421, @#0177440
	check #-1, @#0177442
	bit #04000, @#0177450
	bne *+6
	jmp @#failed
	mov #011, r5
	mov #040, @#0177450
	mov #-1, @#0177442
	mov #026, @#0177446      ; sector 22 is outside RK geometry
	mov #021, @#0177440
	check #02000, @#0177454
	check #-1, @#0177442
	mov #012, r5
	mov #01400, @#0177446    ; head 3 is outside RK geometry
	mov #021, @#0177440
	check #02000, @#0177454
	mov #012345, r0
	halt
disk_irq
	inc @#014000
	rti
failed
	halt

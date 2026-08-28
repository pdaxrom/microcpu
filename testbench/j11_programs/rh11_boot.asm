; Same RH0 bootstrap as k1801vm1/lsi11/main.c, expressed as assembly.
; Only the bootstrap is deposited in FRAM: NO OS/boot block is preloaded.
	cpu dcj-11
	org 0
	jmp @#boot
	org 02000
	dw 042115                   ; "MD" signature
boot
	mov #02000, sp
	mov #0, r0                  ; unit 0
	mov #0177440, r1
	mov #040, 010(r1)           ; controller clear
	mov r0, 010(r1)
drive_type
	mov 012(r1), r2
	bpl drive_type
	bic #0177377, r2
	asl r2
	asl r2
	mov #3, r3                  ; PACK ACK + GO
	bis r2, r3
	mov r3, (r1)
wait_pack
	tstb (r1)
	bpl wait_pack
	mov #-01000, 2(r1)          ; 512 words / TWO sectors, as in lsi11
	clr 4(r1)
	clr 6(r1)
	clr 020(r1)
	mov #021, r3                ; READ + GO
	bis r2, r3
	mov r3, (r1)
wait_read
	tstb (r1)
	bpl wait_read
	clr r2
	clr r3
	mov #02020, r4
	clr r5
	clr pc

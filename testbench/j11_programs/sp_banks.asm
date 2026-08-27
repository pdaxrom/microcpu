	cpu dcj-11
	org 0
	br start
	org 4
	dw fail_kernel
	dw 0
	org 014
	dw breakpoint
	dw 0
	org 0100

start
	mov #010000, sp
	clr r4
	mov #012345, r5
	; Select PM=U while staying in K, then initialize the inactive USP.
	mov #030000, -(sp)
	mov #setup_usp, -(sp)
	rti
setup_usp
	mov #014000, -(sp)
	mtpi sp
	; Initialize SSP through the same previous-mode register mechanism.
	mov #010000, -(sp)
	mov #setup_ssp, -(sp)
	rti
setup_ssp
	mov #012000, -(sp)
	mtpd sp
	mov #0140000, -(sp)
	mov #user_entry, -(sp)
	rti

user_entry
	cmp #014000, sp
	bne fail_guest
	mov #014010, sp
	bpt
	br fail_guest

super_entry
	cmp #012000, sp
	bne fail_guest
	mov #012010, sp
	bpt
	br fail_guest

kernel_return
	cmp #010000, sp
	bne fail_kernel
	cmp #2, r4
	bne fail_kernel
	cmp #012345, r5
	bne fail_kernel
	mov #012345, r0
	halt

fail_guest
	halt			; user/supervisor HALT enters the kernel failure vector

fail_kernel
	clr r0
	halt

breakpoint
	cmp #07774, sp
	bne fail_kernel
	inc r4
	cmp #1, r4
	bne from_super
	mfpi sp
	mov (sp)+, r2
	cmp #014010, r2
	bne fail_kernel
	mov #super_entry, (sp)
	mov #040000, 2(sp)
	rtt			; RTT must switch to the supervisor bank too

from_super
	cmp #2, r4
	bne fail_kernel
	mfpd sp
	mov (sp)+, r2
	cmp #012010, r2
	bne fail_kernel
	mov #kernel_return, (sp)
	clr 2(sp)
	rti

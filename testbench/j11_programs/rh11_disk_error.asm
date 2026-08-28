	cpu dcj-11
	org 0
	mov #04000, sp
	mov @#014002, r5          ; scenario provided as data, never opcodes
	mov #06000, @#0177444
	mov #-2, @#0177442
	mov #012345, @#06000
	mov #067770, @#06002
	cmp #3, r5
	beq do_write
	cmp #4, r5
	beq do_write
	cmp #7, r5
	beq do_write
	cmp #011, r5
	beq do_write
	cmp #012, r5
	bne not_cache_fault
	mov #-0401, @#0177442
	br do_write
not_cache_fault
	cmp #010, r5
	bne do_read
	mov #-1, @#0177460
	mov #01025, @#0177446
do_read
	mov #021, @#0177440
	br check_error
do_write
	mov #023, @#0177440
check_error
	tst @#0177440
	bpl failed
	bit #0200, @#0177440
	beq failed
	cmp #7, r5
	beq check_nem
	cmp #012, r5
	beq check_nem
	bit #0100000, @#0177450
	beq failed
	br passed
check_nem
	cmp #-1, @#0177442
	bne failed
	cmp #012, r5
	beq check_nem_second_sector
	cmp #06002, @#0177444
	bne failed
	br check_nem_bit
check_nem_second_sector
	cmp #07000, @#0177444
	bne failed
check_nem_bit
	bit #04000, @#0177450
	beq failed
passed
	mov #012345, r0
	halt
failed
	clr r0
	halt

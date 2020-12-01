begin:
    set		r0, counter
    set		r1, 1
    set		r2, $ff
    set		r3, $0f
    set		r4, 4
    load	r5, r0, 0
    load	r6, r0, 1

loop:
    and 	r7, r5, r3
    and		r8, r6, r3
    shl		r8, r8, r4
    or		r8, r8, r7
    store	r8, r2, 0

    add		r5, r5, r1
    beq		r5, $0a
    set		pc, loop
    set		r5, 0
    add		r6, r6, r1
loop1:
    set		pc, loop

counter:
    db		0
    db		0

    ds		$100-*, $ff

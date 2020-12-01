begin:
    set r0, counter
    set r1, 1
    set r2, $ff
    load r3, r0, 0
loop:
    store	r3, r2, 0
    add		r3, r3, r1
    set		pc, loop

counter:
    db		0

    ds		$100-*, $ff

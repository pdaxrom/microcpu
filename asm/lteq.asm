begin:
    set		r0, 1
    set		r1, 2
    set		r2, $ff

    lt		r3, r0, r1
    store	r3, r2, 0

    lt		r3, r1, r0
    store	r3, r2, 0

    eq		r3, r1, r0
    store	r3, r2, 0

    eq		r3, r1, r1
    store	r3, r2, 0

    set		pc, begin

    ds		$100-*, $ff

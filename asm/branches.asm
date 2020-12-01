begin:
    set		r0, $aa
    set		r1, $bb
    set		r2, $ff
    store	r2, r2, 0

    beq		r0, $12
    set		pc, next
    store	r0, r2, 0
    set		pc, begin
next:
    store	r1, r2, 0
    set		pc, begin

    ds		$100-*, $ff

start:
    nop
start1:
    set		r0, 16
    load	r1, r0, 0
    store	r1, r0, 1
    set		lr, data
    set		pc, start1
data:
    set		r2, '1'
    set		r3, '2'

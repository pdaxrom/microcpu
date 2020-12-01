begin:
    set r0, rdata
    load r1, r0, 0
    load r2, r0, 1
    load r3, r0, 2
    load r4, r0, 3
    load r5, r0, 4
    load r6, r0, 5
    load r7, r0, 6
    load r8, r0, 7

    set r0, rdata
    store r8, r0, 0
    store r7, r0, 1
    store r6, r0, 2
    store r5, r0, 3
    store r4, r0, 4
    store r3, r0, 5
    store r2, r0, 6
    store r1, r0, 7

    set	pc, begin

rdata:
    db $11, $22, $33, $44, $55, $66, $77, $88
    ds	$100-*

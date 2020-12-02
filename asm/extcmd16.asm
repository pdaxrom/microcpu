;
; 16 bit demo
;

start:
    set		v0, 8
    set		lr, /begin
    shl		lr, lr, v0
    set		lr, begin
    set		v0, 0
    add		pc, lr, v0

    ds	$e0-*, $ff

begin:
    set		v0, 8
    set		v1, 0
    set		lr, $ff
    shl		lr, lr, v0
    add		v1, pc, v1
    shr		v1, v1, v0
    store	v1, lr, 0
    nop
    nop
    nop
    nop
    b	next
    nop
    nop
    nop
    nop
next:
    set		v0, 8
    set		v1, 0
    set		lr, $ff
    shl		lr, lr, v0
    add		v1, pc, v1
    shr		v1, v1, v0
    store	v1, lr, 0
    nop
    nop
    nop
    nop
    b	begin

    ds	$200-*, $ff

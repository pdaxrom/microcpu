begin:
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
    nop
    nop
    nop
    nop
    b	begin
halt:
    b halt

    dw	next+2,1,2,3

    ds	$100-*, $ff

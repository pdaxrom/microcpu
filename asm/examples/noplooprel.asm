    macro nop
    mov v0,v0
    endm

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

    ds	$100-*

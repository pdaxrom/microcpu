    macro nop
    mov v0,v0
    endm

begin:
    nop
    nop
    nop
    nop
    setl	pc, next
    nop
    nop
    nop
    nop
next:
    nop
    nop
    nop
    nop
    setl	pc, begin

    ds	$100-*

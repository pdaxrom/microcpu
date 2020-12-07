    macro nop
    mov v0,v0
    endm

begin:
    mov		r7, r6
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

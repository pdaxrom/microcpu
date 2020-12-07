    macro nop
    mov		v0,v0
    endm

    macro bsr
    mov		lr, pc
    b		#1
    endm

    macro rts
    add		pc, lr, 3
    endm

    macro push
    strh	#1, sp, 0
    strl	#1, sp, 1
    sub		sp, sp, 2
    endm

    macro pop
    add		sp, sp, 2
    ldrh	#1, sp, 0
    ldrl	#1, sp, 1
    endm

    macro set
    seth	#1, /#2
    setl	#1, #2
    endm

begin:
    set		v0, $abcd
    nop
    bsr		subr
    nop
    nop
    nop
    b		begin

subr:
    push	lr
    pop		lr
    rts

    ds	$100-*

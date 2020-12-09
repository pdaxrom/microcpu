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
    set		sp, $00fe
    set		v1, numbers
    seth	v0, 0
loop:
    ldrl	v0, v1, 0
    cmp		v0, 0
    beq		loopexit
    bsr		printnum
    add		v1, v1, 1
    b		loop
loopexit:
    b		begin

printnum:
    push	v1
    push	v2
    set		v1, $ff00
printnum1:
    ldrl	v2, v1, 0
    and		v2, v2, 2
    beq		printnum2
    b		printnum1
printnum2:
    strl	v0, v1, 1
    pop		v2
    pop		v1
    rts

numbers:
    db	"Hello, World!", 10, 13, 0

    ds	$100-*

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
    str		#1, sp, 0
    sub		sp, sp, 2
    endm

    macro pop
    add		sp, sp, 2
    ldr		#1, sp, 0
    endm

    macro set
    setl	#1, #2
    seth	#1, /#2
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
    set		v1, $ff00
    strl	v0, v1, 0
    pop		v1
    rts

numbers:
    db	3, 2, 1, 0, 4, 5, 6, 7, 8, 9, $a, $b, $c, $d, $e, $f, 0

    ds	$100-*

    seth	v0, $ff
    setl	v0, 0
    seth	v1, 0
    setl	v1, 0
loop:
    strl	v1, v0, 0
    add		v1, v1, 1
    b		loop

    ds	$100-*

    seth	v0, $ff
    setl	v0, 0
    seth	v1, 0
    setl	v1, 0
    seth	v2, /data
    setl	v2, data
    strl	v1, v2, 0
    strh	v1, v2, 1
loop:
    ldrl	v1, v2, 0
    strl	v1, v0, 0
    add		v1, v1, 1
    strl	v1, v2, 0

    ldrl	v1, v2, 1
    strl	v1, v0, 0
    sub		v1, v1, 1
    strl	v1, v2, 1
    b		loop

data:
    db $AA, $BB

    ds	$100-*

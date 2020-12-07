    mov		v0, v1
    add		v0, v1, v2
    add		v0, v2, 7
    cmp		v0, v1
    cmp		v0, 3
    cmp		v0, $0f

    ds	$100-*

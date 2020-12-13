start mov		v1, v2
    add		v0, v1, v2
    add		v0, v2, 7
    cmp		v0, v1
    cmp		v0, 3
    cmp		v0, $0f

    b		$3ff

    ds	$380

    b		start

    ds	$400-*

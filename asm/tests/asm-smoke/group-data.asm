org $0000

    ldrl v0, v1, v2
    ldrl v0, v1, 1
    strl v0, v1, v2
    strl v0, v1, 2
    ldr  v0, v1, v2
    ldr  v0, v1, 3
    str  v0, v1, v2
    str  v0, v1, 4

    setl v0, $12
    seth v0, /$1234
    movl v0, v1
    movh v0, v1
    mov  v0, v1

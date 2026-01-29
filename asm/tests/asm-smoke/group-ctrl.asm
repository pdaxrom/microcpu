org $0020

    setp v0
    getp v1

    eq   v0, v1
    eq   v0, 1
    ne   v0, v1
    ne   v0, 2
    mi   v0, v1
    mi   v0, 3
    vs   v0, v1
    vs   v0, 4
    lt   v0, v1
    lt   v0, 5
    ge   v0, v1
    ge   v0, 6
    ltu  v0, v1
    ltu  v0, 7
    geu  v0, v1
    geu  v0, 8
    btc  v0, v1
    btc  v0, 9
    bts  v0, v1
    bts  v0, 10

    sws
    swu

    b forward
backward:
    b start
forward:
start:
    b backward

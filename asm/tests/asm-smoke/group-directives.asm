org $0100
include include.inc

equ1 equ $10 + 2
equ2 equ /$1234

db 1, 2, 3, "A", 0
dw $1234, 0, equ1
ds 4
ds 2, $ff
align 2
chksum

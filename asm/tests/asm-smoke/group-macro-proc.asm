org $0200

macro mset
    setl #1, #2
    seth #1, /#2
endm

mset v0, $1234

proc1 proc
    global proc_global
proc_label:
    add v0, v0, 1
proc_global:
    b proc_end
proc_end:
    endp

public start
extern ext_target
entry start

start:
    dw local
    dw ext_target
    setl v0, ext_target
    seth v0, /ext_target
local:
    db $cc

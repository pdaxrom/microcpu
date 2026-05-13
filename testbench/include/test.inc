TEST_INTR equ $fffd
TEST_STATUS equ $fffe

macro test_pass
	setl v3, TEST_STATUS
	seth v3, /TEST_STATUS
	setl v4, 0
	strl v4, v3, 0
	b *
endm

macro check_eq16
	setl v3, #2
	seth v3, /#2
	setl v4, #3
	eq #1, v3
	b fail
endm

macro check_eq4
	setl v4, #3
	eq #1, #2
	b fail
endm

macro check_ne4
	setl v4, #3
	ne #1, #2
	b fail
endm

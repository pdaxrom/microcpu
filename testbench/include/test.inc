TEST_INTR equ $fffd
TEST_STATUS equ $fffe
TEST_EXPECT_READ_ADDR_LO equ $fff4
TEST_EXPECT_READ_ADDR_HI equ $fff5
TEST_EXPECT_READ_DATA equ $fff6
TEST_EXPECT_READ_COMMIT equ $fff7
TEST_EXPECT_ADDR_LO equ $fff8
TEST_EXPECT_ADDR_HI equ $fff9
TEST_EXPECT_DATA equ $fffa
TEST_EXPECT_COMMIT equ $fffb
TEST_UART_EXPECT equ $fffc

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

macro expect_write
	setl v3, TEST_EXPECT_ADDR_LO
	seth v3, /TEST_EXPECT_ADDR_LO
	setl v4, #1
	strl v4, v3, 0
	setl v3, TEST_EXPECT_ADDR_HI
	seth v3, /TEST_EXPECT_ADDR_HI
	setl v4, /#1
	strl v4, v3, 0
	setl v3, TEST_EXPECT_DATA
	seth v3, /TEST_EXPECT_DATA
	setl v4, #2
	strl v4, v3, 0
	setl v3, TEST_EXPECT_COMMIT
	seth v3, /TEST_EXPECT_COMMIT
	strl v4, v3, 0
endm

macro expect_read
	setl v3, TEST_EXPECT_READ_ADDR_LO
	seth v3, /TEST_EXPECT_READ_ADDR_LO
	setl v4, #1
	strl v4, v3, 0
	setl v3, TEST_EXPECT_READ_ADDR_HI
	seth v3, /TEST_EXPECT_READ_ADDR_HI
	setl v4, /#1
	strl v4, v3, 0
	setl v3, TEST_EXPECT_READ_DATA
	seth v3, /TEST_EXPECT_READ_DATA
	setl v4, #2
	strl v4, v3, 0
	setl v3, TEST_EXPECT_READ_COMMIT
	seth v3, /TEST_EXPECT_READ_COMMIT
	strl v4, v3, 0
endm

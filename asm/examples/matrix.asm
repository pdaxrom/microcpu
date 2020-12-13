	macro nop
	mov	v0,v0
	endm

	macro bsr
	mov	lr, pc
	b	#1
	endm

	macro rts
	add	pc, lr, 3
	endm

	macro push
	str	#1, sp, 0
	sub	sp, sp, 2
	endm

	macro pop
	add	sp, sp, 2
	ldr	#1, sp, 0
	endm

	macro set
	setl	#1, #2
	seth	#1, /#2
	endm

UART_ADDR	equ	$e6b0
GPIOPORT	equ	$e6d0

;
; MATRIX LED (MAX7219)
;
; GPIO 0 - DIN
; GPIO 1 - CS
; GPIO 2 - CLK
;

PIN_DIN		equ	1
PIN_CS		equ	2
PIN_CLK		equ	4

REG_NOOP	equ	0
REG_DIGIT_0	equ	$100
REG_DIGIT_1	equ	$200
REG_DIGIT_2	equ	$300
REG_DIGIT_3	equ	$400
REG_DIGIT_4	equ	$500
REG_DIGIT_5	equ	$600
REG_DIGIT_6	equ	$700
REG_DIGIT_7	equ	$800
REG_DECODE_MODE	equ	$900
REG_INTENSITY	equ	$A00
REG_SCAN_LIMIT	equ	$B00
REG_SHUTDOWN	equ	$C00
REG_DISP_TEST	equ	$F00

begin	set	sp, $03fe
	set	v1, GPIOPORT
	setl	v0, $7
	strl	v0, v1, 3
	ldrl	v0, v1, 1
	set	v2, $fff8
	and	v0, v0, v2
	or	v0, v0, PIN_CS
	strl	v0, v1, 1

	set	v0, $2000
	bsr	delay

	set	v0, t_1
	bsr	printstr

	bsr	disp_init
	set	v0, heart
	bsr	disp

	set	v0, t_5
	bsr	printstr

stop	b	stop

dump	proc
	push	lr
	push	v0
	bsr	printhex
	set	v0, nl
	bsr	printstr
	pop	v0
	pop	lr
	rts
	endp

heart	db	$38, $7C, $7E, $3F, $3F, $7E, $7C, $38

t_1	db	10, 13, 'Init', 0
t_2	db	10, 13, 'Intensity', 0
t_3	db	10, 13, 'Clean', 0
t_4	db	10, 13, 'Show', 0
t_5	db	10, 13, 'Stop', 0
nl	db	10, 13, 0


	align	2

delay	proc
	push	v0
loop	sub	v0, v0, 1
	beq	exit
	b	loop
exit	pop	v0
	rts
	endp

disp_init proc
	push	lr
	push	v0
	set	v0, $03
	bsr	disp_intensity
	bsr	disp_clean
	pop	v0
	pop	lr
	rts
	endp

disp_intensity proc
	push	lr
	push	v1
	push	v0
	push	v0
	set	v0, REG_SHUTDOWN | $01
	bsr	senddata
	set	v0, REG_DECODE_MODE | $00
	bsr	senddata
	set	v0, REG_SCAN_LIMIT | $07
	bsr	senddata
	pop	v0
	set	v1, REG_INTENSITY
	or	v0, v0, v1
	bsr	senddata
	pop	v0
	pop	v1
	pop	lr
	rts
	endp

disp_clean proc
	push	lr
	push	v0
	push	v1
	push	v2

	set	v0, REG_DIGIT_0
	set	v1, $100
	set	v2, 8

loop	bsr	senddata
	add	v0, v0, v1
	sub	v2, v2, 1
	beq	exit
	b	loop

exit	pop	v2
	pop	v1
	pop	v0
	pop	lr
	rts
	endp

disp	proc
	push	lr
	push	v1
	push	v2
	push	v3
	push	v0

	set	v0, REG_SHUTDOWN | $01
	bsr	senddata
	set	v0, REG_DECODE_MODE | $00
	bsr	senddata
	set	v0, REG_SCAN_LIMIT | $07
	bsr	senddata
	pop	v3
	push	v3
	set	v0, REG_DIGIT_0
	set	v1, $100
	set	v2, 8

loop	ldrl	v0, v3, 0
	bsr	senddata
	add	v0, v0, v1
	add	v3, v3, 1
	sub	v2, v2, 1
	beq	exit
	b	loop

exit	pop	v0
	pop	v3
	pop	v2
	pop	v1
	pop	lr
	rts
	endp

senddata proc
	push	lr
	push	v0
	push	v1
	push	v2
	push	v3
	push	v4

	set	v1, GPIOPORT
	ldrl	v4, v1, 1
	or	v4, v4, PIN_CS
	xor	v4, v4, PIN_CS
	strl	v4, v1, 1

	set	v2, 16
	set	v3, $8000

loop	ldrl	v4, v1, 1
	or	v4, v4, PIN_DIN
	tst	v0, v3
	beq	bitlo
	b	writebit
bitlo	xor	v4, v4, PIN_DIN
writebit strl	v4, v1, 1

	or	v4, v4, PIN_CLK
	strl	v4, v1, 1
	xor	v4, v4, PIN_CLK
	strl	v4, v1, 1

	shl	v0, v0, 1
	sub	v2, v2, 1
	beq	exit
	b	loop

exit	or	v4, v4, PIN_CS
	strl	v4, v1, 1

	pop	v4
	pop	v3
	pop	v2
	pop	v1
	pop	v0
	pop	lr
	rts
	endp

printhex proc
	push	lr
	push	v0
	shr	v0, v0, 8
	bsr	printhex8
	pop	v0
	bsr	printhex8
	pop	lr
	rts
	endp

printhex8 proc
	push	lr
	push	v0
	push	v1
	set	v1, nums
	seth	v0, 0
	push	v0
	shr	v0, v0, 4
	add	v0, v1, v0
	ldrl	v0, v0, 0
	bsr	putchar
	pop	v0
	and	v0, v0, 15
	add	v0, v1, v0
	ldrl	v0, v0, 0
	bsr	putchar
	pop	v1
	pop	v0
	pop	lr
	rts
nums	db	'0123456789ABCDEF'
	endp

printstr proc
	push	lr
	push	v0
	push	v1
	mov	v1, v0
	seth	v0, 0
.1	ldrl	v0, v1, 0
	cmp	v0, 0
	beq	.2
	bsr	putchar
	add	v1, v1, 1
	b	.1
.2	pop	v1
	pop	v0
	pop	lr
	rts
	endp

putchar	proc
	push	v1
	push	v2
	set	v1, UART_ADDR
.1	ldrl	v2, v1, 0
	and	v2, v2, 2
	beq	.2
	b	.1
.2	strl	v0, v1, 1
	pop	v2
	pop	v1
	rts
	endp

getchar	proc
	push	v1
	set	v1, UART_ADDR
	seth	v0, 0
.1	ldrl	v0, v1, 0
	and	v0, v0, 1
	beq	.1
	ldrl	v0, v1, 1
	pop	v1
	rts
	endp

	ds	$400-*

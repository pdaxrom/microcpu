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

VEC_RESET	equ	$0000
VEC_INTR	equ	$0002
VEC_MEMERR	equ	$0004
VEC_GETCHAR	equ	$0006
VEC_PUTCHAR	equ	$0008
VEC_PUTSTR	equ	$000a

;
; HCMS matrix display
;
; GPIO 0 - DIN
; GPIO 1 - CE
; GPIO 2 - CLK
; GPIO 3 - RS
; GPIO 4 - RESET
;

PIN_DIN		equ	1
PIN_CE		equ	2
PIN_CLK		equ	4
PIN_RS		equ	8
PIN_RESET	equ	16

	org	$100

begin	set	sp, $07fe
	set	v1, GPIOPORT

; set PIN_CE=1, PIN_RESET=1, PIN_DIN=0, PIN_CLK=0, PIN_RS=0
	ldrl	v0, v1, 1
	setl	v2, $ff^(PIN_DIN | PIN_CLK | PIN_RS)
	and	v0, v0, v2
	setl	v2, (PIN_CE | PIN_RESET)
	or	v0, v0, v2
	strl	v0, v1, 1

; enable output for PIN_DIN, PIN_CE, PIN_CLK, PIN_RS, PIN_RESET
	ldrl	v0, v1, 3
	setl	v2, (PIN_DIN | PIN_CE | PIN_CLK | PIN_RS | PIN_RESET)
	or	v0, v0, v2
	strl	v0, v1, 3

	set	v0, $2000
	bsr	delay

	set	v0, t_1
	bsr	VEC_PUTSTR

	bsr	disp_init

;	set	v0, fb_blank
;	bsr	disp_show

	set	v0, font+32*5
	bsr	disp_show

	set	v0, t_5
	bsr	VEC_PUTSTR

stop	b	stop

dump	proc
	push	lr
	push	v0
	bsr	printhex
	set	v0, nl
	bsr	VEC_PUTSTR
	pop	v0
	pop	lr
	rts
	endp

t_1	db	10, 13, 'Init1', 0
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
	push	v1
	push	v2

	set	v1, GPIOPORT
	ldrl	v2, v1, 1
	setl	v0, (PIN_RS | PIN_RESET | PIN_CE)
	or	v2, v2, v0
	strl	v2, v1, 1

	setl	v0, $ff^PIN_RESET
	and	v2, v2, v0
	strl	v2, v1, 1

	setl	v0, 40
	bsr	delay

	setl	v0, PIN_RESET
	or	v2, v2, v0
	strl	v2, v1, 1

	setl	v0, $4c		; 0101 1100
	bsr	disp_cmd

	pop	v2
	pop	v1
	pop	v0
	pop	lr
	rts
	endp

disp_cmd proc
	push	lr
	push	v1
	push	v2
	push	v3

	set	v1, GPIOPORT
	ldrl	v2, v1, 1
	setl	v3, PIN_RS
	or	v2, v2, v3
	strl	v2, v1, 1

	bsr	disp_ce_low

	set	v3, 8

loop	bsr	sendbyte
	sub	v3, v3, 1
	beq	exit
	b	loop

exit	bsr	disp_ce_high
	pop	v3
	pop	v2
	pop	v1
	pop	lr
	rts
	endp

disp_show proc
	push	lr
	push	v0
	push	v1
	push	v2
	push	v3
	push	v4

	set	v1, GPIOPORT
	ldrl	v2, v1, 1
	setl	v3, $ff^PIN_RS
	and	v2, v2, v3
	strl	v2, v1, 1

	bsr	disp_ce_low

	mov	v2, v0

	set	v3, 40
	set	v4, 120
	bsr	send40

	set	v3, 40
	set	v4, 80
	bsr	send40

	set	v3, 40
	set	v4, 40
	bsr	send40

	set	v3, 40
	set	v4, 0
	bsr	send40

	bsr	disp_ce_high

	pop	v4
	pop	v3
	pop	v2
	pop	v1
	pop	v0
	pop	lr
	rts

send40	push	lr
loop	ldrl	v0, v2, v4
	bsr	sendbyte
	add	v4, v4, 1
	sub	v3, v3, 1
	beq	exit
	b	loop
exit	pop	lr
	rts
	endp

sendbyte proc
	push	lr
	push	v0
	push	v1
	push	v2
	push	v3
	push	v4

	set	v2, 8
	set	v3, $80

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

exit	pop	v4
	pop	v3
	pop	v2
	pop	v1
	pop	v0
	pop	lr
	rts
	endp

disp_ce_low proc
	push	v1
	push	v4
	set	v1, GPIOPORT
	ldrl	v4, v1, 1
	or	v4, v4, PIN_CE
	xor	v4, v4, PIN_CE
	strl	v4, v1, 1
	pop	v4
	pop	v1
	rts
	endp

disp_ce_high proc
	push	v1
	push	v4
	set	v1, GPIOPORT
	ldrl	v4, v1, 1
	or	v4, v4, PIN_CE
	strl	v4, v1, 1
	pop	v4
	pop	v1
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
	bsr	VEC_PUTCHAR
	pop	v0
	and	v0, v0, 15
	add	v0, v1, v0
	ldrl	v0, v0, 0
	bsr	VEC_PUTCHAR
	pop	v1
	pop	v0
	pop	lr
	rts
nums	db	'0123456789ABCDEF'
	endp

font	db	 $FF, $FF, $FF, $FF, $FF	; 00
	db	 $FF, $FF, $FF, $FF, $FF	; 01
	db	 $1C, $3E, $7C, $3E, $1C	; 02
	db	 $FF, $FF, $FF, $FF, $FF	; 03
	db	 $FF, $FF, $FF, $FF, $FF	; 04
	db	 $FF, $FF, $FF, $FF, $FF	; 05
	db	 $FF, $FF, $FF, $FF, $FF	; 06
	db	 $FF, $FF, $FF, $FF, $FF	; 07
	db	 $FF, $FF, $FF, $FF, $FF	; 08
	db	 $FF, $FF, $FF, $FF, $FF	; 09
	db	 $FF, $FF, $FF, $FF, $FF	; 0A
	db	 $FF, $FF, $FF, $FF, $FF	; 0B
	db	 $FF, $FF, $FF, $FF, $FF	; 0C
	db	 $FF, $FF, $FF, $FF, $FF	; 0D
	db	 $FF, $FF, $FF, $FF, $FF	; 0E
	db	 $FF, $FF, $FF, $FF, $FF	; 0F
	db	 $FF, $FF, $FF, $FF, $FF	; 10
	db	 $FF, $FF, $FF, $FF, $FF	; 11
	db	 $FF, $FF, $FF, $FF, $FF	; 12
	db	 $FF, $FF, $FF, $FF, $FF	; 13
	db	 $FF, $FF, $FF, $FF, $FF	; 14
	db	 $FF, $FF, $FF, $FF, $FF	; 15
	db	 $FF, $FF, $FF, $FF, $FF	; 16
	db	 $FF, $FF, $FF, $FF, $FF	; 17
	db	 $FF, $FF, $FF, $FF, $FF	; 18
	db	 $FF, $FF, $FF, $FF, $FF	; 19
	db	 $FF, $FF, $FF, $FF, $FF	; 1A
	db	 $FF, $FF, $FF, $FF, $FF	; 1B
	db	 $FF, $FF, $FF, $FF, $FF	; 1C
	db	 $FF, $FF, $FF, $FF, $FF	; 1D
	db	 $FF, $FF, $FF, $FF, $FF	; 1E
	db	 $FF, $FF, $FF, $FF, $FF	; 1F
	db	 $00, $00, $00, $00, $00	; ' '
	db	 $00, $00, $5F, $00, $00	; '!'
	db	 $00, $07, $00, $07, $00	; '"'
	db	 $14, $7F, $14, $7F, $14	; '#'
	db	 $24, $2A, $7F, $2A, $12	; '$'
	db	 $23, $13, $08, $64, $62	; '%'
	db	 $36, $49, $55, $22, $50	; '&'
	db	 $00, $05, $03, $00, $00	; '''
	db	 $00, $1C, $22, $41, $00	; '('
	db	 $00, $41, $22, $1C, $00	; ')'
	db	 $08, $2A, $1C, $2A, $08	; '*'
	db	 $08, $08, $3E, $08, $08	; '+'
	db	 $00, $50, $30, $00, $00	; ','
	db	 $08, $08, $08, $08, $08	; '-'
	db	 $00, $60, $60, $00, $00	; '.'
	db	 $20, $10, $08, $04, $02	; '/'
	db	 $3E, $51, $49, $45, $3E	; '0'
	db	 $00, $42, $7F, $40, $00	; '1'
	db	 $42, $61, $51, $49, $46	; '2'
	db	 $21, $41, $45, $4B, $31	; '3'
	db	 $18, $14, $12, $7F, $10	; '4'
	db	 $27, $45, $45, $45, $39	; '5'
	db	 $3C, $4A, $49, $49, $30	; '6'
	db	 $01, $71, $09, $05, $03	; '7'
	db	 $36, $49, $49, $49, $36	; '8'
	db	 $06, $49, $49, $29, $1E	; '9'
	db	 $00, $36, $36, $00, $00	; ':'
	db	 $00, $56, $36, $00, $00	; ';'
	db	 $00, $08, $14, $22, $41	; '<'
	db	 $14, $14, $14, $14, $14	; '='
	db	 $41, $22, $14, $08, $00	; '>'
	db	 $02, $01, $51, $09, $06	; '?'
	db	 $32, $49, $79, $41, $3E	; '@'
	db	 $7E, $11, $11, $11, $7E	; 'A'
	db	 $7F, $49, $49, $49, $36	; 'B'
	db	 $3E, $41, $41, $41, $22	; 'C'
	db	 $7F, $41, $41, $22, $1C	; 'D'
	db	 $7F, $49, $49, $49, $41	; 'E'
	db	 $7F, $09, $09, $01, $01	; 'F'
	db	 $3E, $41, $41, $51, $32	; 'G'
	db	 $7F, $08, $08, $08, $7F	; 'H'
	db	 $00, $41, $7F, $41, $00	; 'I'
	db	 $20, $40, $41, $3F, $01	; 'J'
	db	 $7F, $08, $14, $22, $41	; 'K'
	db	 $7F, $40, $40, $40, $40	; 'L'
	db	 $7F, $02, $04, $02, $7F	; 'M'
	db	 $7F, $04, $08, $10, $7F	; 'N'
	db	 $3E, $41, $41, $41, $3E	; 'O'
	db	 $7F, $09, $09, $09, $06	; 'P'
	db	 $3E, $41, $51, $21, $5E	; 'Q'
	db	 $7F, $09, $19, $29, $46	; 'R'
	db	 $46, $49, $49, $49, $31	; 'S'
	db	 $01, $01, $7F, $01, $01	; 'T'
	db	 $3F, $40, $40, $40, $3F	; 'U'
	db	 $1F, $20, $40, $20, $1F	; 'V'
	db	 $7F, $20, $18, $20, $7F	; 'W'
	db	 $63, $14, $08, $14, $63	; 'X'
	db	 $03, $04, $78, $04, $03	; 'Y'
	db	 $61, $51, $49, $45, $43	; 'Z'
	db	 $00, $00, $7F, $41, $41	; '['
	db	 $02, $04, $08, $10, $20	; '\'
	db	 $41, $41, $7F, $00, $00	; ']'
	db	 $04, $02, $01, $02, $04	; '^'
	db	 $40, $40, $40, $40, $40	; '_'
	db	 $00, $01, $02, $04, $00	; '`'
	db	 $20, $54, $54, $54, $78	; 'a'
	db	 $7F, $48, $44, $44, $38	; 'b'
	db	 $38, $44, $44, $44, $20	; 'c'
	db	 $38, $44, $44, $48, $7F	; 'd'
	db	 $38, $54, $54, $54, $18	; 'e'
	db	 $08, $7E, $09, $01, $02	; 'f'
	db	 $08, $14, $54, $54, $3C	; 'g'
	db	 $7F, $08, $04, $04, $78	; 'h'
	db	 $00, $44, $7D, $40, $00	; 'i'
	db	 $20, $40, $44, $3D, $00	; 'j'
	db	 $00, $7F, $10, $28, $44	; 'k'
	db	 $00, $41, $7F, $40, $00	; 'l'
	db	 $7C, $04, $18, $04, $78	; 'm'
	db	 $7C, $08, $04, $04, $78	; 'n'
	db	 $38, $44, $44, $44, $38	; 'o'
	db	 $7C, $14, $14, $14, $08	; 'p'
	db	 $08, $14, $14, $18, $7C	; 'q'
	db	 $7C, $08, $04, $04, $08	; 'r'
	db	 $48, $54, $54, $54, $20	; 's'
	db	 $04, $3F, $44, $40, $20	; 't'
	db	 $3C, $40, $40, $20, $7C	; 'u'
	db	 $1C, $20, $40, $20, $1C	; 'v'
	db	 $3C, $40, $30, $40, $3C	; 'w'
	db	 $44, $28, $10, $28, $44	; 'x'
	db	 $0C, $50, $50, $50, $3C	; 'y'
	db	 $44, $64, $54, $4C, $44	; 'z'
	db	 $00, $08, $36, $41, $00	; '{'
	db	 $00, $00, $7F, $00, $00	; '|'
	db	 $00, $41, $36, $08, $00	; '}'
	db	 $08, $08, $2A, $1C, $08	; '~'
	db	 $08, $1C, $2A, $08, $08	; ' '

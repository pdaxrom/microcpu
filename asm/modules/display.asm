;
; HCMS matrix display
;
; GPIO 0 - DIN
; GPIO 1 - CE
; GPIO 2 - CLK
; GPIO 3 - RS
; GPIO 4 - BLANK
; GPIO 5 - REG_LATCH
;

PIN_DIN		equ	1
PIN_CE		equ	2
PIN_CLK		equ	4
PIN_RS		equ	8
PIN_BLANK	equ	16
PIN_REG_LATCH	equ	32

	include ../include/pseudo.inc
	include ../include/devmap.inc

	org	$f000

begin	dw	$5aa5		; module header
	dw	end		; length
	dw	modname		; module name
	dw	$0000		; module version
	b	modinit
	b	set_outreg
	b	disp_putchar	; disp_putchar
	b	disp_getkey	; disp_getkey
	b	disp_showtextbuf
	dw	0		; disp_getstring

modname	db	'Display & keys', 0

	align	1

modinit	proc
	push	lr
	set	v1, GPIO_ADDR

; set PIN_CE=1, PIN_BLANK=1, PIN_DIN=0, PIN_CLK=0, PIN_RS=0, PIN_REG_LATCH=0
	ldrl	v0, v1, 1
	setl	v2, $ff^(PIN_DIN | PIN_CLK | PIN_RS | PIN_REG_LATCH)
	and	v0, v0, v2
	setl	v2, PIN_CE
	or	v0, v0, v2
	strl	v0, v1, 1

	set	v0, $2000
	bsr	delay

	bsr	disp_init

	setl	v0, $ff
	bsr	set_outreg

	set	v0, textscr
	bsr	disp_showtextbuf

	pop	lr
	rts
	endp

;		 01234567
textscr	db	"pdaXrom "
	db	"uCPU 1.2"

	align	1

delay	proc
	push	v0
loop	sub	v0, v0, 1
	bne	loop, v0, 0
	pop	v0
	rts
	endp

disp_init proc
	push	lr
	set	v1, GPIO_ADDR
	ldrl	v2, v1, 1
	setl	v0, (PIN_RS | PIN_CE)
	or	v2, v2, v0
	setl	v0, $ff^PIN_BLANK
	and	v2, v2, v0
	strl	v2, v1, 1

	setl	v0, 40
	bsr	delay

	setl	v0, $4c		; 0101 1100
	bsr	disp_cmd
	pop	lr
	rts
	endp

disp_cmd proc
	sub	sp, sp, 10
	str	lr, sp, 10
	str	v1, sp, 8
	str	v2, sp, 6
	str	v3, sp, 4
	str	v4, sp, 2

	set	v1, GPIO_ADDR
	ldrl	v2, v1, 1
	setl	v3, PIN_RS
	or	v2, v2, v3
	strl	v2, v1, 1

	bsr	disp_ce_low

	set	v3, 8

loop	bsr	sendbyte
	sub	v3, v3, 1
	bne	loop, v3, 0

	bsr	disp_ce_high

	ldr	v4, sp, 2
	ldr	v3, sp, 4
	ldr	v2, sp, 6
	ldr	v1, sp, 8
	ldr	lr, sp, 10
	add	sp, sp, 10
	rts
	endp

disp_putchar proc
	push	lr
	push	v0
	push	v1
	push	v2
	push	v3

	seth	v0, 0
	seth	v1, 0
	set	v2, ctrlchr
loop	ldrl	v1, v2, 0
	beq	printc, v1, 0
	bne	next, v1, v0
	ldr	pc, v2, 1
next	add	v2, v2, 3
	b	loop
printc	set	v3, charpos
	ldr	v1, v3, 0
	set	v2, 32
	beq	exit, v1, v2
	set	v2, textbuf
	strl	v0, v2, v1
	inc	v1
	str	v1, v3, 0
exitupd mov	v0, v2
	set	v3, 16
	blt	exitupd1, v1, v3
	sub	v1, v1, v3
	add	v0, v0, v1
exitupd1 bsr	disp_showtextbuf

exit	pop	v3
	pop	v2
	pop	v1
	pop	v0
	pop	lr
	rts

clrscr	set	v2, textbuf
	set	v1, 32
	clr	v0
clrscr1	sub	v1, v1, 2
	str	v0, v2, v1
	bne	clrscr1, v1, 0
	set	v3, charpos
	str	v1, v3, 0
	b	exitupd

delete	set	v3, charpos
	ldr	v1, v3, 0
	beq	exit, v1, 0
	dec	v1
	str	v1, v3, 0
	set	v2, textbuf
	clr	v0
	strl	v0, v2, v1
	b	exitupd

ctrlchr	db	$0a
	dw	clrscr
	db	$0c
	dw	clrscr
	db	$7f
	dw	delete
	db	0
	align	1
	endp

disp_showtextbuf proc
	sub	sp, sp, 12
	str	lr, sp, 12
	str	v0, sp, 10
	str	v1, sp, 8
	str	v2, sp, 6
	str	v3, sp, 4
	str	v4, sp, 2

	set	v1, GPIO_ADDR
	ldrl	v2, v1, 1
	setl	v3, $ff^PIN_RS
	and	v2, v2, v3
	strl	v2, v1, 1

	bsr	disp_ce_low

;	set	v4, 24
;	bsr	print8

;	set	v4, 16
;	bsr	print8

	set	v4, 8
	bsr	print8

	set	v4, 0
	bsr	print8

	bsr	disp_ce_high

	ldr	v4, sp, 2
	ldr	v3, sp, 4
	ldr	v2, sp, 6
	ldr	v1, sp, 8
	ldr	v0, sp, 10
	ldr	lr, sp, 12
	add	sp, sp, 12
	rts

print8	push	lr
	seth	v2, 0
	set	v3, 8
loop	ldrl	v2, v4, v0
	bsr	putchar
	add	v4, v4, 1
	sub	v3, v3, 1
	bne	loop, v3, 0
	pop	lr
	rts
; v2 - char
putchar sub	sp, sp, 6
	str	lr, sp, 6
	str	v0, sp, 4
	str	v3, sp, 2
	set	v3, font
putch1	beq	putch2, v2, 0
	add	v3, v3, 5
	sub	v2, v2, 1
	b	putch1
putch2	set	v2, 5
putch3	ldr	v0, v3, 0
	bsr	sendbyte
	add	v3, v3, 1
	sub	v2, v2, 1
	bne	putch3, v2, 0
	ldr	v3, sp, 2
	ldr	v0, sp, 4
	ldr	lr, sp, 6
	add	sp, sp, 6
	rts
	endp

sendbyte proc
	sub	sp, sp, 12
	str	lr, sp, 12
	str	v0, sp, 10
	str	v1, sp, 8
	str	v2, sp, 6
	str	v3, sp, 4
	str	v4, sp, 2

	set	v2, 8
	set	v3, $80
loop	ldrl	v4, v1, 1
	or	v4, v4, PIN_DIN
	bts	v0, v3
	xor	v4, v4, PIN_DIN
	strl	v4, v1, 1

	or	v4, v4, PIN_CLK
	strl	v4, v1, 1
	xor	v4, v4, PIN_CLK
	strl	v4, v1, 1

	shl	v0, v0, 1
	sub	v2, v2, 1
	bne	loop, v2, 0

	ldr	v4, sp, 2
	ldr	v3, sp, 4
	ldr	v2, sp, 6
	ldr	v1, sp, 8
	ldr	v0, sp, 10
	ldr	lr, sp, 12
	add	sp, sp, 12
	rts
	endp

disp_ce_low proc
	ldrl	v4, v1, 1
	or	v4, v4, PIN_CE
	xor	v4, v4, PIN_CE
	strl	v4, v1, 1
	rts
	endp

disp_ce_high proc
	ldrl	v4, v1, 1
	or	v4, v4, PIN_CE
	strl	v4, v1, 1
	rts
	endp

set_outreg proc
	sub	sp, sp, 8
	str	lr, sp, 8
	str	v1, sp, 6
	str	v2, sp, 4
	str	v4, sp, 2
	set	v1, GPIO_ADDR
	bsr	sendbyte
	ldrl	v4, v1, 1
	setl	v2, PIN_REG_LATCH
	or	v4, v4, v2
	strl	v4, v1, 1
	xor	v4, v4, v2
	strl	v4, v1, 1
	ldr	v4, sp, 2
	ldr	v2, sp, 4
	ldr	v1, sp, 6
	ldr	lr, sp, 8
	add	sp, sp, 8
	rts
	endp

disp_getkey proc
	sub	sp, sp, 10
	str	lr, sp, 10
	str	v1, sp, 8
	str	v2, sp, 6
	str	v3, sp, 4
	str	v4, sp, 2
	seth	v0, 0
	mov	v4, v0
	clr	v2
	set	v3, 8
	set	v1, GPIO_ADDR
loop	mov	v0, v3
	or	v0, v0, v4
	bsr	set_outreg
	ldrl	v0, v1, 0
	shr	v0, v0, 4
	bne	key, v0, 0
	add	v2, v2, 4
	shl	v3, v3, 1
	seth	v3, 0
	bne	loop, v3, 0
	clr	v0
exit	set	v1, kmap
	ldrl	v0, v1, v0
	ldr	v4, sp, 2
	ldr	v3, sp, 4
	ldr	v2, sp, 6
	ldr	v1, sp, 8
	ldr	lr, sp, 10
	add	sp, sp, 10
	rts
key	add	v2, v2, 1
	shr	v0, v0, 1
	bne	key, v0, 0
	mov	v0, v2
	b	exit
kmap	db	$ff
	db	$00, $01, $04, $07
	db	$0a, $02, $05, $08
	db	$0b, $03, $06, $09
	db	$0f, $0e, $0d, $0c
	db	$10, $11, $12, $13
	align	1
	endp

font	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00
	db	 $00, $00, $00, $00, $00

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

	align	1
	chksum
end

textbuf	ds	32, 0
charpos	dw	0

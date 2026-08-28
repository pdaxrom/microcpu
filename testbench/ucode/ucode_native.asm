; Native ucode ISA regression: source assembly, never hand-written ROM words.
cpu ucode
include ../../ucode/v2/pseudo.inc

macro assert_equal
	eq #1, #2
	b *                     ; testbench watchdog reports the failing uPC
endm

macro check_ldi
	seth v0, $a5
	ldi8 v0, #1
	assert_equal v0, v1
	inc v1
endm

org $0000
	b start
bus_error_entry
	gget v0, 10
	assert_equal v0, 1
	ldi8 v0, 2
	gset v0, 10             ; successful completion after the deliberate fault
	b *

start
	ldi8 v0, 0
	sub v0, v0, 1          ; FFFF, C=borrow=1
	ldi8 v1, 0
	cbnz v0, carry_nonzero
	b *
carry_nonzero
	cbz v1, carry_zero
	b *
carry_zero
	adc v2, v1, 0          ; CBZ/CBNZ must preserve carry
	assert_equal v2, 1
	adc v2, v0, 1          ; low word wraps, C=1
	adc v3, v0, 0          ; middle word wraps, C=1
	adc v4, v1, 0          ; high word receives carry
	assert_equal v2, 0
	assert_equal v3, 0
	assert_equal v4, 1
	sub v2, v1, 1
	sbc v3, v1, 0          ; propagate borrow through a zero word
	getf v4
	assert_equal v3, v0
	assert_equal v4, 9
	sbc v3, v0, 15         ; FFFF - 15 - borrow = FFEF, no new borrow
	getf v4
	assert_equal v4, 8
	ldi8 v4, 2
zero_branch_loop
	sub v4, v4, 1
	cbnz v4, zero_branch_loop
	cbnz v4, zero_branch_fail
	cbz v0, zero_branch_fail
	cbnz pc, zero_branch_done ; native PC read is byte address + 1
zero_branch_fail
	b *
zero_branch_done
	ldi8 v0, 0
	sub v0, v0, 1
	getf v4
	ldi8 v0, $80
	getf v1
	assert_equal v4, v1     ; LDI8 preserves NZVC
	assert_equal v4, 9      ; negative + borrow from 0 - 1

	ldi8 v1, 0
; Every unsigned 8-bit constant must clear a nonzero high byte.
	check_ldi 0
	check_ldi 1
	check_ldi 2
	check_ldi 3
	check_ldi 4
	check_ldi 5
	check_ldi 6
	check_ldi 7
	check_ldi 8
	check_ldi 9
	check_ldi 10
	check_ldi 11
	check_ldi 12
	check_ldi 13
	check_ldi 14
	check_ldi 15
	check_ldi 16
	check_ldi 17
	check_ldi 18
	check_ldi 19
	check_ldi 20
	check_ldi 21
	check_ldi 22
	check_ldi 23
	check_ldi 24
	check_ldi 25
	check_ldi 26
	check_ldi 27
	check_ldi 28
	check_ldi 29
	check_ldi 30
	check_ldi 31
	check_ldi 32
	check_ldi 33
	check_ldi 34
	check_ldi 35
	check_ldi 36
	check_ldi 37
	check_ldi 38
	check_ldi 39
	check_ldi 40
	check_ldi 41
	check_ldi 42
	check_ldi 43
	check_ldi 44
	check_ldi 45
	check_ldi 46
	check_ldi 47
	check_ldi 48
	check_ldi 49
	check_ldi 50
	check_ldi 51
	check_ldi 52
	check_ldi 53
	check_ldi 54
	check_ldi 55
	check_ldi 56
	check_ldi 57
	check_ldi 58
	check_ldi 59
	check_ldi 60
	check_ldi 61
	check_ldi 62
	check_ldi 63
	check_ldi 64
	check_ldi 65
	check_ldi 66
	check_ldi 67
	check_ldi 68
	check_ldi 69
	check_ldi 70
	check_ldi 71
	check_ldi 72
	check_ldi 73
	check_ldi 74
	check_ldi 75
	check_ldi 76
	check_ldi 77
	check_ldi 78
	check_ldi 79
	check_ldi 80
	check_ldi 81
	check_ldi 82
	check_ldi 83
	check_ldi 84
	check_ldi 85
	check_ldi 86
	check_ldi 87
	check_ldi 88
	check_ldi 89
	check_ldi 90
	check_ldi 91
	check_ldi 92
	check_ldi 93
	check_ldi 94
	check_ldi 95
	check_ldi 96
	check_ldi 97
	check_ldi 98
	check_ldi 99
	check_ldi 100
	check_ldi 101
	check_ldi 102
	check_ldi 103
	check_ldi 104
	check_ldi 105
	check_ldi 106
	check_ldi 107
	check_ldi 108
	check_ldi 109
	check_ldi 110
	check_ldi 111
	check_ldi 112
	check_ldi 113
	check_ldi 114
	check_ldi 115
	check_ldi 116
	check_ldi 117
	check_ldi 118
	check_ldi 119
	check_ldi 120
	check_ldi 121
	check_ldi 122
	check_ldi 123
	check_ldi 124
	check_ldi 125
	check_ldi 126
	check_ldi 127
	check_ldi 128
	check_ldi 129
	check_ldi 130
	check_ldi 131
	check_ldi 132
	check_ldi 133
	check_ldi 134
	check_ldi 135
	check_ldi 136
	check_ldi 137
	check_ldi 138
	check_ldi 139
	check_ldi 140
	check_ldi 141
	check_ldi 142
	check_ldi 143
	check_ldi 144
	check_ldi 145
	check_ldi 146
	check_ldi 147
	check_ldi 148
	check_ldi 149
	check_ldi 150
	check_ldi 151
	check_ldi 152
	check_ldi 153
	check_ldi 154
	check_ldi 155
	check_ldi 156
	check_ldi 157
	check_ldi 158
	check_ldi 159
	check_ldi 160
	check_ldi 161
	check_ldi 162
	check_ldi 163
	check_ldi 164
	check_ldi 165
	check_ldi 166
	check_ldi 167
	check_ldi 168
	check_ldi 169
	check_ldi 170
	check_ldi 171
	check_ldi 172
	check_ldi 173
	check_ldi 174
	check_ldi 175
	check_ldi 176
	check_ldi 177
	check_ldi 178
	check_ldi 179
	check_ldi 180
	check_ldi 181
	check_ldi 182
	check_ldi 183
	check_ldi 184
	check_ldi 185
	check_ldi 186
	check_ldi 187
	check_ldi 188
	check_ldi 189
	check_ldi 190
	check_ldi 191
	check_ldi 192
	check_ldi 193
	check_ldi 194
	check_ldi 195
	check_ldi 196
	check_ldi 197
	check_ldi 198
	check_ldi 199
	check_ldi 200
	check_ldi 201
	check_ldi 202
	check_ldi 203
	check_ldi 204
	check_ldi 205
	check_ldi 206
	check_ldi 207
	check_ldi 208
	check_ldi 209
	check_ldi 210
	check_ldi 211
	check_ldi 212
	check_ldi 213
	check_ldi 214
	check_ldi 215
	check_ldi 216
	check_ldi 217
	check_ldi 218
	check_ldi 219
	check_ldi 220
	check_ldi 221
	check_ldi 222
	check_ldi 223
	check_ldi 224
	check_ldi 225
	check_ldi 226
	check_ldi 227
	check_ldi 228
	check_ldi 229
	check_ldi 230
	check_ldi 231
	check_ldi 232
	check_ldi 233
	check_ldi 234
	check_ldi 235
	check_ldi 236
	check_ldi 237
	check_ldi 238
	check_ldi 239
	check_ldi 240
	check_ldi 241
	check_ldi 242
	check_ldi 243
	check_ldi 244
	check_ldi 245
	check_ldi 246
	check_ldi 247
	check_ldi 248
	check_ldi 249
	check_ldi 250
	check_ldi 251
	check_ldi 252
	check_ldi 253
	check_ldi 254
	check_ldi 255

; Every native destination except PC.
	seth r1, $ff
	ldi8 r1, 7
	assert_equal r1, 7
	seth r2, $ff
	ldi8 r2, 7
	assert_equal r2, 7
	seth r3, $ff
	ldi8 r3, 7
	assert_equal r3, 7
	seth r4, $ff
	ldi8 r4, 7
	assert_equal r4, 7
	seth r5, $ff
	ldi8 r5, 7
	assert_equal r5, 7
	seth r6, $ff
	ldi8 r6, 7
	assert_equal r6, 7
	seth r7, $ff
	ldi8 r7, 7
	assert_equal r7, 7

; All context is reset, including the high half.
	ldi8 v2, 0
	ldi8 v3, 64
check_clear
	ggetr v0, v2
	assert_equal v0, 0
	inc v2
	bne check_clear, v2, v3

; Distinct immediate indexes must not alias each other or native service ports.
	ldi8 v0, 1
	gset v0, 0
	ldi8 v0, 2
	gset v0, 1
	ldi8 v0, 3
	gset v0, 2
	ldi8 v0, 4
	gset v0, 3
	ldi8 v0, 5
	gset v0, 4
	ldi8 v0, 6
	gset v0, 5
	ldi8 v0, 7
	gset v0, 6
	ldi8 v0, 8
	gset v0, 7
	ldi8 v0, 9
	gset v0, 8
	ldi8 v0, 10
	gset v0, 9
	ldi8 v0, 13
	gset v0, 12
	ldi8 v0, 14
	gset v0, 13
	ldi8 v0, 15
	gset v0, 14
	ldi8 v0, 17
	gset v0, 16
	ldi8 v0, 18
	gset v0, 17
	ldi8 v0, 19
	gset v0, 18
	ldi8 v0, 20
	gset v0, 19
	ldi8 v0, 21
	gset v0, 20
	ldi8 v0, 22
	gset v0, 21
	ldi8 v0, 23
	gset v0, 22
	ldi8 v0, 24
	gset v0, 23
	ldi8 v0, 25
	gset v0, 24
	ldi8 v0, 26
	gset v0, 25
	ldi8 v0, 27
	gset v0, 26
	ldi8 v0, 28
	gset v0, 27
	ldi8 v0, 29
	gset v0, 28
	ldi8 v0, 30
	gset v0, 29
	ldi8 v0, 31
	gset v0, 30
	ldi8 v0, 32
	gset v0, 31
	ldi8 v0, 33
	gset v0, 32
	ldi8 v0, 34
	gset v0, 33
	ldi8 v0, 35
	gset v0, 34
	ldi8 v0, 36
	gset v0, 35
	ldi8 v0, 37
	gset v0, 36
	ldi8 v0, 38
	gset v0, 37
	ldi8 v0, 39
	gset v0, 38
	ldi8 v0, 40
	gset v0, 39
	ldi8 v0, 41
	gset v0, 40
	ldi8 v0, 42
	gset v0, 41
	ldi8 v0, 43
	gset v0, 42
	ldi8 v0, 44
	gset v0, 43
	ldi8 v0, 45
	gset v0, 44
	ldi8 v0, 46
	gset v0, 45
	ldi8 v0, 47
	gset v0, 46
	ldi8 v0, 48
	gset v0, 47
	ldi8 v0, 49
	gset v0, 48
	ldi8 v0, 50
	gset v0, 49
	ldi8 v0, 51
	gset v0, 50
	ldi8 v0, 52
	gset v0, 51
	ldi8 v0, 53
	gset v0, 52
	ldi8 v0, 54
	gset v0, 53
	ldi8 v0, 55
	gset v0, 54
	ldi8 v0, 56
	gset v0, 55
	ldi8 v0, 57
	gset v0, 56
	ldi8 v0, 58
	gset v0, 57
	ldi8 v0, 59
	gset v0, 58
	ldi8 v0, 60
	gset v0, 59
	ldi8 v0, 61
	gset v0, 60
	ldi8 v0, 62
	gset v0, 61
	ldi8 v0, 63
	gset v0, 62
	ldi8 v0, 64
	gset v0, 63
	gget v0, 0
	ldi8 v1, 1
	assert_equal v0, v1
	gget v0, 1
	ldi8 v1, 2
	assert_equal v0, v1
	gget v0, 2
	ldi8 v1, 3
	assert_equal v0, v1
	gget v0, 3
	ldi8 v1, 4
	assert_equal v0, v1
	gget v0, 4
	ldi8 v1, 5
	assert_equal v0, v1
	gget v0, 5
	ldi8 v1, 6
	assert_equal v0, v1
	gget v0, 6
	ldi8 v1, 7
	assert_equal v0, v1
	gget v0, 7
	ldi8 v1, 8
	assert_equal v0, v1
	gget v0, 8
	ldi8 v1, 9
	assert_equal v0, v1
	gget v0, 9
	ldi8 v1, 10
	assert_equal v0, v1
	gget v0, 12
	ldi8 v1, 13
	assert_equal v0, v1
	gget v0, 13
	ldi8 v1, 14
	assert_equal v0, v1
	gget v0, 14
	ldi8 v1, 15
	assert_equal v0, v1
	gget v0, 16
	ldi8 v1, 17
	assert_equal v0, v1
	gget v0, 17
	ldi8 v1, 18
	assert_equal v0, v1
	gget v0, 18
	ldi8 v1, 19
	assert_equal v0, v1
	gget v0, 19
	ldi8 v1, 20
	assert_equal v0, v1
	gget v0, 20
	ldi8 v1, 21
	assert_equal v0, v1
	gget v0, 21
	ldi8 v1, 22
	assert_equal v0, v1
	gget v0, 22
	ldi8 v1, 23
	assert_equal v0, v1
	gget v0, 23
	ldi8 v1, 24
	assert_equal v0, v1
	gget v0, 24
	ldi8 v1, 25
	assert_equal v0, v1
	gget v0, 25
	ldi8 v1, 26
	assert_equal v0, v1
	gget v0, 26
	ldi8 v1, 27
	assert_equal v0, v1
	gget v0, 27
	ldi8 v1, 28
	assert_equal v0, v1
	gget v0, 28
	ldi8 v1, 29
	assert_equal v0, v1
	gget v0, 29
	ldi8 v1, 30
	assert_equal v0, v1
	gget v0, 30
	ldi8 v1, 31
	assert_equal v0, v1
	gget v0, 31
	ldi8 v1, 32
	assert_equal v0, v1
	gget v0, 32
	ldi8 v1, 33
	assert_equal v0, v1
	gget v0, 33
	ldi8 v1, 34
	assert_equal v0, v1
	gget v0, 34
	ldi8 v1, 35
	assert_equal v0, v1
	gget v0, 35
	ldi8 v1, 36
	assert_equal v0, v1
	gget v0, 36
	ldi8 v1, 37
	assert_equal v0, v1
	gget v0, 37
	ldi8 v1, 38
	assert_equal v0, v1
	gget v0, 38
	ldi8 v1, 39
	assert_equal v0, v1
	gget v0, 39
	ldi8 v1, 40
	assert_equal v0, v1
	gget v0, 40
	ldi8 v1, 41
	assert_equal v0, v1
	gget v0, 41
	ldi8 v1, 42
	assert_equal v0, v1
	gget v0, 42
	ldi8 v1, 43
	assert_equal v0, v1
	gget v0, 43
	ldi8 v1, 44
	assert_equal v0, v1
	gget v0, 44
	ldi8 v1, 45
	assert_equal v0, v1
	gget v0, 45
	ldi8 v1, 46
	assert_equal v0, v1
	gget v0, 46
	ldi8 v1, 47
	assert_equal v0, v1
	gget v0, 47
	ldi8 v1, 48
	assert_equal v0, v1
	gget v0, 48
	ldi8 v1, 49
	assert_equal v0, v1
	gget v0, 49
	ldi8 v1, 50
	assert_equal v0, v1
	gget v0, 50
	ldi8 v1, 51
	assert_equal v0, v1
	gget v0, 51
	ldi8 v1, 52
	assert_equal v0, v1
	gget v0, 52
	ldi8 v1, 53
	assert_equal v0, v1
	gget v0, 53
	ldi8 v1, 54
	assert_equal v0, v1
	gget v0, 54
	ldi8 v1, 55
	assert_equal v0, v1
	gget v0, 55
	ldi8 v1, 56
	assert_equal v0, v1
	gget v0, 56
	ldi8 v1, 57
	assert_equal v0, v1
	gget v0, 57
	ldi8 v1, 58
	assert_equal v0, v1
	gget v0, 58
	ldi8 v1, 59
	assert_equal v0, v1
	gget v0, 59
	ldi8 v1, 60
	assert_equal v0, v1
	gget v0, 60
	ldi8 v1, 61
	assert_equal v0, v1
	gget v0, 61
	ldi8 v1, 62
	assert_equal v0, v1
	gget v0, 62
	ldi8 v1, 63
	assert_equal v0, v1
	gget v0, 63
	ldi8 v1, 64
	assert_equal v0, v1

; Direct high-index jumps and indexed jumps use the same physical context.
	set v0, direct_target
	gset v0, 63
	gget pc, 63
	b *
direct_target
	set v0, indexed_target
	ldi8 v2, 63
	gsetr v0, v2
	ggetr pc, v2
	b *
indexed_target
pc_source
	gset pc, 62
	set v0, pc_source+1
	gget v1, 62
	assert_equal v0, v1

; CMP/bit skips consume their own operands, not stale ALU flags.
	set v0, $8000
	ldi8 v1, 1
	lt v0, v1
	b *
	geu v0, v1
	b *
	btc v0, 1
	b *
	bts v1, 1
	b *

; Full-range absolute calls, nested RAM returns, flag-neutral jumps/returns.
	set v0, $ffff
	add v0, v0, 1
	getf v4
	call upper_call
after_call
	getf v3
	assert_equal v3, v4
	set v1, after_call
	assert_equal lr, v1
	set v2, $a55a
	xor v2, v2, v2
	assert_equal v2, 0

; Raw byte load preserves the high half; word load replaces both halves.
	set v0, $ab34
	ldi8 v1, $80
	str v0, v1, 0
	set v2, $ffff
	ldrl v2, v1, 0
	set v3, $ff34
	assert_equal v2, v3
	ldr v2, v1, 0
	assert_equal v2, v0
	strl v0, v1, 1
	ldr v2, v1, 0
	set v3, $3434
	assert_equal v2, v3
	ldr v2, v1, 1          ; deliberate odd word access -> bus_error_entry
	b *

; Upper half of the address space also sets encoded instruction bit 3:
; it must not turn CALL/JMP into ALU operations or overwrite a random Rd.
	ds $1600-*
upper_call
	getf v3
	assert_equal v3, v4
	gset lr, 61
	call nested_call
after_nested
	set v1, after_nested
	assert_equal lr, v1
	gget lr, 61
	jmp upper_return
	b *
upper_return
	ret
nested_call
	ret

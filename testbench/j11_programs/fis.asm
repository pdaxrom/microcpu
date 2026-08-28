	include fis_test.inc
table
	; 1+1=2; 1-2=-1; 2*3=6; 3/2=1.5.
	dw do_add, 040200, 0, 040200, 0, 040400, 0, 0340, 0
	dw do_sub, 040400, 0, 040200, 0, 0140200, 0, 0350, 0
	dw do_mul, 040500, 0, 040400, 0, 040700, 0, 0340, 0
	dw do_div, 040400, 0, 040500, 0, 040300, 0, 0340, 0
	; Cancellation, signed/dirty zeros, division by zero.
	dw do_add, 0140200, 0, 040200, 0, 0, 0, 0344, 0
	dw do_add, 0100001, 1, 040200, 0, 040200, 0, 0340, 0
	dw do_sub, 040200, 0, 077, 0177777, 0140200, 0, 0350, 0
	dw do_mul, 040200, 0, 0100077, 1, 0, 0, 0344, 0
	dw do_div, 0, 0, 040200, 0, 040200, 0, 0353, 1
	; Overflow, underflow, lowest representable exponent, halfway rounding.
	dw do_add, 077600, 0, 077600, 0, 077600, 0, 0342, 1
	dw do_mul, 040000, 0, 0200, 0, 0200, 0, 0352, 1
	dw do_div, 040200, 0, 0200, 1, 0200, 1, 0340, 0
	dw do_add, 032200, 0, 040200, 0, 040200, 1, 0340, 0
end_table

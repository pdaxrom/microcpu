;
; Object-mode Small-C microcpu runtime.
;

include ../../asm/include/pseudo.inc
include microcpu_cc.inc

public __eq
public __ne
public __lt
public __ge
public __gt
public __le
public __ult
public __uge
public __ugt
public __ule
public __lneg
public __neg16
public __mul16
public __udiv16
public __umod16
public __sdiv16
public __smod16
public __shl16
public __sar16
public __switch
public _strlen
public _memset
public _memcpy
public _memcmp
public _strcpy
public _strcmp
public _strchr
public _putchar
public _puts
public _getchar

include lib16.asm
include string.asm
include uart.asm

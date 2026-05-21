/*
** Small-C Compiler -- microcpu Back End.
** Based on Small-C 2.2 Revision Level 117 by J. E. Hendrix.
*/
#include <stdio.h>
#include "cc.h"
#include "host_compat.h"

extern int code[PCODES];

int setcodes_microcpu()
{
  int i;

  i = 0;
  while(i < PCODES) code[i++] = "\000; unsupported Small-C p-code\n";

  code[ADD12]   = "\000add v0, v0, v1\n";
  code[ADD1n]   = "\000?add v0, v0, <n>\n??";
  code[ADD21]   = "\000add v1, v1, v0\n";
  code[ADD2n]   = "\000?add v1, v1, <n>\n??";
  code[ADDSP]   = "\000?add sp, sp, <n>\n??";
  code[AND12]   = "\000and v0, v0, v1\n";
  code[ANEG1]   = "\000inv v0, v0\nadd v0, v0, 1\n";
  code[ARGCNTn] = "\000";
  code[ASL12]   = "\000jsr __shl16\n";
  code[ASR12]   = "\000jsr __sar16\n";
  code[CALL1]   = "\000add lr, pc, 3\nmov pc, v0\n";
  code[CALLm]   = "\000jsr <m>\n";
  code[BYTE_]   = "\000db ";
  code[BYTEn]   = "\000db <n>\n";
  code[BYTEr0]  = "\000ds <n>\n";
  code[COM1]    = "\000inv v0, v0\n";
  code[COMMAn]  = "\000, <n>\n";
  code[DBL1]    = "\000shl v0, v0, 1\n";
  code[DBL2]    = "\000shl v1, v1, 1\n";
  code[DECbp]   = "\000ldrl v2, v1, 0\nsub v2, v2, 1\nstrl v2, v1, 0\n";
  code[DECwp]   = "\000ldr v2, v1, 0\nsub v2, v2, 1\nstr v2, v1, 0\n";
  code[DIV12]   = "\000jsr __sdiv16\n";
  code[DIV12u]  = "\000jsr __udiv16\n";
  code[ENTER]   = "\000str lr, sp, 0\nsub sp, sp, 2\nstr v4, sp, 0\nmov v4, sp\nsub sp, sp, 2\n";
  code[EQ10f]   = "\000eq v0, 0\nb _<n>\n";
  code[EQ12]    = "\000jsr __eq\n";
  code[GE10f]   = "\000ge v0, 0\nb _<n>\n";
  code[GE12]    = "\000jsr __ge\n";
  code[GE12u]   = "\000jsr __uge\n";
  code[GETb1m]  = "\000set v2, <m>\nldrl v0, v2, 0\nsxt v0, v0\n";
  code[GETb1mu] = "\000set v2, <m>\nldrl v0, v2, 0\nseth v0, 0\n";
  code[GETb1p]  = "\000ldrl v0, v1, 0\nsxt v0, v0\n";
  code[GETb1pu] = "\000ldrl v0, v1, 0\nseth v0, 0\n";
  code[GETb1s]  = "\000set v2, <n>\nadd v2, v4, v2\nldrl v0, v2, 0\nsxt v0, v0\n";
  code[GETb1su] = "\000set v2, <n>\nadd v2, v4, v2\nldrl v0, v2, 0\nseth v0, 0\n";
  code[GETw1m]  = "\000set v2, <m>\nldr v0, v2, 0\n";
  code[GETw1m_] = "\000set v2, <m>\nldr v0, v2, 0\n";
  code[GETw1n]  = "\000?set v0, <n>\n?clr v0?\n";
  code[GETw1p]  = "\000ldr v0, v1, 0\n";
  code[GETw1s]  = "\000set v2, <n>\nadd v2, v4, v2\nldr v0, v2, 0\n";
  code[GETw2m]  = "\000set v2, <m>\nldr v1, v2, 0\n";
  code[GETw2n]  = "\000?set v1, <n>\n?clr v1?\n";
  code[GETw2p]  = "\000ldr v1, v1, 0\n";
  code[GETw2s]  = "\000set v2, <n>\nadd v2, v4, v2\nldr v1, v2, 0\n";
  code[GT10f]   = "\000clr v2\nlt v2, v0\nb _<n>\n";
  code[GT12]    = "\000jsr __gt\n";
  code[GT12u]   = "\000jsr __ugt\n";
  code[INCbp]   = "\000ldrl v2, v1, 0\nadd v2, v2, 1\nstrl v2, v1, 0\n";
  code[INCwp]   = "\000ldr v2, v1, 0\nadd v2, v2, 1\nstr v2, v1, 0\n";
  code[WORD_]   = "\000dw ";
  code[WORDn]   = "\000dw <n>\n";
  code[WORDr0]  = "\000#dw 0\n#";
  code[JMPm]    = "\000b _<n>\n";
  code[LABm]    = "\000_<n>:\n";
  code[LE10f]   = "\000clr v2\nge v2, v0\nb _<n>\n";
  code[LE12]    = "\000jsr __le\n";
  code[LE12u]   = "\000jsr __ule\n";
  code[LNEG1]   = "\000jsr __lneg\n";
  code[LT10f]   = "\000lt v0, 0\nb _<n>\n";
  code[LT12]    = "\000jsr __lt\n";
  code[LT12u]   = "\000jsr __ult\n";
  code[MOD12]   = "\000jsr __smod16\n";
  code[MOD12u]  = "\000jsr __umod16\n";
  code[MOVE21]  = "\000mov v1, v0\n";
  code[MUL12]   = "\000jsr __mul16\n";
  code[MUL12u]  = "\000jsr __mul16\n";
  code[NE10f]   = "\000ne v0, 0\nb _<n>\n";
  code[NE12]    = "\000jsr __ne\n";
  code[NEARm]   = "\000dw _<n>\n";
  code[OR12]    = "\000or v0, v0, v1\n";
  code[PLUSn]   = "\000set v2, <n>\nadd v1, v1, v2\n";
  code[POINT1l] = "\000set v0, _<l>\nset v2, <n>\nadd v0, v0, v2\n";
  code[POINT1m] = "\000set v0, <m>\n";
  code[POINT1s] = "\000set v0, <n>\nadd v0, v4, v0\n";
  code[POINT2m] = "\000set v1, <m>\n";
  code[POINT2m_]= "\000set v1, <m>\n";
  code[POINT2s] = "\000set v1, <n>\nadd v1, v4, v1\n";
  code[POP2]    = "\000add sp, sp, 2\nldr v1, sp, 0\n";
  code[PUSH1]   = "\000str v0, sp, 0\nsub sp, sp, 2\n";
  code[PUSH2]   = "\000str v1, sp, 0\nsub sp, sp, 2\n";
  code[PUSHm]   = "\000set v2, <m>\nldr v3, v2, 0\nstr v3, sp, 0\nsub sp, sp, 2\n";
  code[PUSHp]   = "\000ldr v2, v1, 0\nstr v2, sp, 0\nsub sp, sp, 2\n";
  code[PUSHs]   = "\000set v2, <n>\nadd v2, v4, v2\nldr v3, v2, 0\nstr v3, sp, 0\nsub sp, sp, 2\n";
  code[PUT_m_]  = "\000";
  code[PUTbm1]  = "\000set v2, <m>\nstrl v0, v2, 0\n";
  code[PUTbp1]  = "\000strl v0, v1, 0\n";
  code[PUTwm1]  = "\000set v2, <m>\nstr v0, v2, 0\n";
  code[PUTwp1]  = "\000str v0, v1, 0\n";
  code[rDEC1]   = "\000#sub v0, v0, 1\n#";
  code[rDEC2]   = "\000#sub v1, v1, 1\n#";
  code[REFm]    = "\000_<n>:\n";
  code[RETURN]  = "\000mov sp, v4\nldr v4, sp, 0\nadd sp, sp, 2\nldr lr, sp, 0\nmov pc, lr\n";
  code[rINC1]   = "\000#add v0, v0, 1\n#";
  code[rINC2]   = "\000#add v1, v1, 1\n#";
  code[SUB_m_]  = "\000";
  code[SUB12]   = "\000sub v0, v0, v1\n";
  code[SUB1n]   = "\000?sub v0, v0, <n>\n??";
  code[SUBbpn]  = "\000ldrl v2, v1, 0\nsub v2, v2, <n>\nstrl v2, v1, 0\n";
  code[SUBwpn]  = "\000ldr v2, v1, 0\nsub v2, v2, <n>\nstr v2, v1, 0\n";
  code[SWAP12]  = "\000mov v2, v0\nmov v0, v1\nmov v1, v2\n";
  code[SWAP1s]  = "\000add sp, sp, 2\nldr v1, sp, 0\nmov v2, v0\nmov v0, v1\nmov v1, v2\nstr v1, sp, 0\nsub sp, sp, 2\n";
  code[SWITCH]  = "\000jsr __switch\n";
  code[XOR12]   = "\000xor v0, v0, v1\n";
}

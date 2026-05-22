/*
** Small-C p-code Back End.
** Emits a compact textual p-code assembly that pcinterp encodes as an
** 8-bit bytecode stream.
*/
#include <stdio.h>
#include "cc.h"
#include "host_compat.h"

extern int output, pcode_argc, litptr, litlab;
extern char *symtab, *cptr, *litq, ssname[NAMESIZE];

#define PCTMP0 0
#define PCTMP1 2

int pcode_switch_mode, pcode_switch_label, pcode_switch_have_label;

int pcode_label(n) int n; {
  outstr("L");
  outdec(n);
  }

int pcode_name(ptr) char *ptr; {
  outname(ptr);
  }

int pcode_islocal(ptr) char *ptr; {
  if(ptr >= STARTLOC && ptr < ENDLOC) return YES;
  return NO;
  }

int pcode_emit_local_op(op, value) char *op; int value; {
  outstr(op);
  fputc(' ', output);
  outdec(value);
  newline();
  }

int pcode_load_tmp(which) int which; {
  if(which == 0) pcode_emit_local_op("llocal", PCTMP0);
  else           pcode_emit_local_op("llocal", PCTMP1);
  }

int pcode_store_tmp(which) int which; {
  if(which == 0) pcode_emit_local_op("slocal", PCTMP0);
  else           pcode_emit_local_op("slocal", PCTMP1);
  }

int pcode_bin_v0_v1(op) char *op; {
  pcode_load_tmp(0);
  pcode_load_tmp(1);
  outline(op);
  pcode_store_tmp(0);
  }

int pcode_bin_v1_v0(op) char *op; {
  pcode_load_tmp(1);
  pcode_load_tmp(0);
  outline(op);
  pcode_store_tmp(0);
  }

int pcode_unary_v0(op) char *op; {
  pcode_load_tmp(0);
  outline(op);
  pcode_store_tmp(0);
  }

int pcode_unsupported(pcode) int pcode; {
  fputs("unsupported internal pcode for stack backend: ", stderr);
  errnum(pcode, stderr);
  fputc(NEWLINE, stderr);
  error("unsupported internal pcode for stack backend");
  return 0;
  }

int pcode_emit_global_op(op, ptr) char *op, *ptr; {
  outstr(op);
  fputc(' ', output);
  pcode_name(ptr + NAME);
  newline();
  }

int pcode_emit_function_addr(ptr) char *ptr; {
  outstr("addr_func ");
  pcode_name(ptr + NAME);
  newline();
  }

int pcode_emit_data_prefix(op) char *op; {
  outstr(op);
  }

int pcode_header() {
  pcode_switch_mode = 0;
  pcode_switch_label = 0;
  pcode_switch_have_label = 0;
  outline("; Small-C p-code assembly");
  outline("; Encoded by pcinterp as 8-bit opcodes with little-endian operands");
  outline("entry _main");
  return 0;
  }

int pcode_trailer() {
  outline("end");
  return 0;
  }

int pcode_public(ident) int ident; {
  if(ident == FUNCTION) {
    outstr("func ");
    pcode_name(ssname);
    newline();
    return 0;
    }
  outstr("data_label ");
  pcode_name(ssname);
  newline();
  return 0;
  }

int pcode_external(name, size, ident) char *name; int size, ident; {
  return 0;
  }

int pcode_dumpzero(size, count) int size, count; {
  int bytes;
  bytes = size * count;
  if(bytes > 0) {
    outstr("zero ");
    outdec(bytes);
    newline();
    }
  return 0;
  }

int pcode_dumplits(size) int size; {
  int k, v;
  k = 0;
  if(size == 1) outstr("data8");
  else          outstr("data16");
  while(k < litptr) {
    v = getint(litq + k, size);
    fputc(' ', output);
    outdec(v);
    k += size;
    }
  newline();
  return 0;
  }

int pcode_call(ptr) char *ptr; {
  if(ptr[CLASS] == AUTOEXT || ptr[CLASS] == EXTERNAL) {
    outstr("ncall ");
    pcode_name(ptr + NAME);
    fputc(' ', output);
    outdec(pcode_argc);
    newline();
    pcode_store_tmp(0);
    return 0;
    }
  outstr("call ");
  pcode_name(ptr + NAME);
  fputc(' ', output);
  outdec(pcode_argc);
  newline();
  pcode_store_tmp(0);
  return 0;
  }

int pcode_outcode(pcode, value) int pcode, value; {
  char *ptr;
  ptr = value;
  switch(pcode) {
    case ADD12:   pcode_bin_v0_v1("add"); return 0;
    case SUB12:   pcode_bin_v0_v1("sub"); return 0;
    case AND12:   pcode_bin_v0_v1("and"); return 0;
    case OR12:    pcode_bin_v0_v1("or");  return 0;
    case XOR12:   pcode_bin_v0_v1("xor"); return 0;
    case ASL12:   pcode_bin_v0_v1("shl"); return 0;
    case ASR12:   pcode_bin_v0_v1("shr"); return 0;
    case MUL12:
    case MUL12u:  pcode_bin_v0_v1("mul"); return 0;
    case DIV12:   pcode_bin_v0_v1("sdiv"); return 0;
    case DIV12u:  pcode_bin_v0_v1("udiv"); return 0;
    case MOD12:   pcode_bin_v0_v1("smod"); return 0;
    case MOD12u:  pcode_bin_v0_v1("umod"); return 0;
    case EQ12:    pcode_bin_v1_v0("eq"); return 0;
    case NE12:    pcode_bin_v1_v0("ne"); return 0;
    case LT12:
    case LT12u:   pcode_bin_v1_v0("lt"); return 0;
    case LE12:
    case LE12u:   pcode_bin_v1_v0("le"); return 0;
    case GT12:
    case GT12u:   pcode_bin_v1_v0("gt"); return 0;
    case GE12:
    case GE12u:   pcode_bin_v1_v0("ge"); return 0;
    case ANEG1:   pcode_unary_v0("neg"); return 0;
    case COM1:    pcode_unary_v0("bnot"); return 0;
    case LNEG1:   pcode_unary_v0("lnot"); return 0;
    case DBL1:
      pcode_load_tmp(0);
      outline("iconst 2");
      outline("mul");
      pcode_store_tmp(0);
      return 0;
    case DBL2:
      pcode_load_tmp(1);
      outline("iconst 2");
      outline("mul");
      pcode_store_tmp(1);
      return 0;

    case GETw1n:
      outstr("iconst ");
      outdec(value);
      newline();
      pcode_store_tmp(0);
      return 0;
    case GETw2n:
      outstr("iconst ");
      outdec(value);
      newline();
      pcode_store_tmp(1);
      return 0;

    case GETw1m:
    case GETw1m_:
      if(pcode_islocal(ptr))
        pcode_emit_local_op("llocal", getint(ptr + OFFSET, 2));
      else
        pcode_emit_global_op("lglobal", ptr);
      pcode_store_tmp(0);
      return 0;
    case GETw2m:
      if(pcode_islocal(ptr))
        pcode_emit_local_op("llocal", getint(ptr + OFFSET, 2));
      else
        pcode_emit_global_op("lglobal", ptr);
      pcode_store_tmp(1);
      return 0;
    case GETb1m:
    case GETb1mu:
      if(pcode_islocal(ptr))
        pcode_emit_local_op("llocal", getint(ptr + OFFSET, 2));
      else
        pcode_emit_global_op("lglobal", ptr);
      pcode_store_tmp(0);
      return 0;
    case GETw1s:
      pcode_emit_local_op("llocal", value);
      pcode_store_tmp(0);
      return 0;
    case GETw2s:
      pcode_emit_local_op("llocal", value);
      pcode_store_tmp(1);
      return 0;
    case GETb1s:
    case GETb1su:
      pcode_emit_local_op("llocal", value);
      pcode_store_tmp(0);
      return 0;

    case PUTwm1:
      pcode_load_tmp(0);
      if(pcode_islocal(ptr))
        pcode_emit_local_op("slocal", getint(ptr + OFFSET, 2));
      else
        pcode_emit_global_op("sglobal", ptr);
      return 0;
    case PUTbm1:
      pcode_load_tmp(0);
      if(pcode_islocal(ptr))
        pcode_emit_local_op("slocal", getint(ptr + OFFSET, 2));
      else
        pcode_emit_global_op("sglobal", ptr);
      return 0;

    case POINT1m:
      if(pcode_islocal(ptr))
        pcode_emit_local_op("addr_local", getint(ptr + OFFSET, 2));
      else if(ptr[IDENT] == FUNCTION)
        pcode_emit_function_addr(ptr);
      else
        pcode_emit_global_op("addr_global", ptr);
      pcode_store_tmp(0);
      return 0;
    case POINT2m:
    case POINT2m_:
      if(pcode_islocal(ptr))
        pcode_emit_local_op("addr_local", getint(ptr + OFFSET, 2));
      else if(ptr[IDENT] == FUNCTION)
        pcode_emit_function_addr(ptr);
      else
        pcode_emit_global_op("addr_global", ptr);
      pcode_store_tmp(1);
      return 0;
    case POINT1s:
      pcode_emit_local_op("addr_local", value);
      pcode_store_tmp(0);
      return 0;
    case POINT2s:
      pcode_emit_local_op("addr_local", value);
      pcode_store_tmp(1);
      return 0;
    case POINT1l:
      outstr("addr_global ");
      pcode_label(litlab);
      newline();
      if(value) {
        outstr("iconst ");
        outdec(value);
        newline();
        outline("add");
        }
      pcode_store_tmp(0);
      return 0;

    case GETw1p:
      pcode_load_tmp(1);
      outline("lword");
      pcode_store_tmp(0);
      return 0;
    case GETw2p:
      pcode_load_tmp(1);
      outline("lword");
      pcode_store_tmp(1);
      return 0;
    case GETb1p:
    case GETb1pu:
      pcode_load_tmp(1);
      outline("lbyte");
      pcode_store_tmp(0);
      return 0;
    case PUTwp1:
      pcode_load_tmp(1);
      pcode_load_tmp(0);
      outline("sword");
      return 0;
    case PUTbp1:
      pcode_load_tmp(1);
      pcode_load_tmp(0);
      outline("sbyte");
      return 0;
    case rINC1:
      pcode_load_tmp(0);
      outline("iconst 1");
      outline("add");
      pcode_store_tmp(0);
      return 0;
    case rDEC1:
      pcode_load_tmp(0);
      outline("iconst 1");
      outline("sub");
      pcode_store_tmp(0);
      return 0;
    case rINC2:
      pcode_load_tmp(1);
      outline("iconst 1");
      outline("add");
      pcode_store_tmp(1);
      return 0;
    case rDEC2:
      pcode_load_tmp(1);
      outline("iconst 1");
      outline("sub");
      pcode_store_tmp(1);
      return 0;

    case JMPm:
      outstr("jmp ");
      pcode_label(value);
      newline();
      return 0;
    case NE10f:
      pcode_load_tmp(0);
      outstr("jz ");
      pcode_label(value);
      newline();
      return 0;
    case EQ10f:
      pcode_load_tmp(0);
      outstr("jnz ");
      pcode_label(value);
      newline();
      return 0;
    case GT10f:
      pcode_load_tmp(0);
      outline("iconst 0");
      outline("le");
      outstr("jnz ");
      pcode_label(value);
      newline();
      return 0;
    case GE10f:
      pcode_load_tmp(0);
      outline("iconst 0");
      outline("lt");
      outstr("jnz ");
      pcode_label(value);
      newline();
      return 0;
    case LT10f:
      pcode_load_tmp(0);
      outline("iconst 0");
      outline("ge");
      outstr("jnz ");
      pcode_label(value);
      newline();
      return 0;
    case LE10f:
      pcode_load_tmp(0);
      outline("iconst 0");
      outline("gt");
      outstr("jnz ");
      pcode_label(value);
      newline();
      return 0;
    case LABm:
      outstr("label ");
      pcode_label(value);
      newline();
      return 0;
    case REFm:
      outstr("data_label ");
      pcode_label(value);
      newline();
      return 0;

    case ARGCNTn:
      pcode_argc = value;
      return 0;
    case CALLm:
      pcode_call(ptr);
      return 0;
    case CALL1:
      pcode_load_tmp(0);
      outstr("icall ");
      outdec(pcode_argc);
      newline();
      pcode_store_tmp(0);
      return 0;
    case ADDSP:
    case ENTER:
      return 0;
    case MOVE21:
      pcode_load_tmp(0);
      pcode_store_tmp(1);
      return 0;
    case POP2:
      pcode_store_tmp(1);
      return 0;
    case PUSH1:
      pcode_load_tmp(0);
      return 0;
    case PUSH2:
      pcode_load_tmp(1);
      return 0;
    case SWAP12:
      pcode_load_tmp(0);
      pcode_load_tmp(1);
      pcode_store_tmp(0);
      pcode_store_tmp(1);
      return 0;
    case SWAP1s:
      pcode_load_tmp(0);
      outline("swap");
      pcode_store_tmp(0);
      return 0;
    case RETURN:
      pcode_load_tmp(0);
      outline("ret");
      return 0;

    case WORDn:
      if(pcode_switch_mode) {
        if(value == 0) {
          pcode_switch_mode = 0;
          pcode_switch_have_label = 0;
          return 0;
          }
        if(pcode_switch_have_label == 0) {
          error("bad switch table");
          return 0;
          }
        pcode_load_tmp(0);
        outstr("iconst ");
        outdec(value);
        newline();
        outline("eq");
        outstr("jnz ");
        pcode_label(pcode_switch_label);
        newline();
        pcode_switch_have_label = 0;
        return 0;
        }
      outstr("data16 ");
      outdec(value);
      newline();
      return 0;
    case BYTEn:
      outstr("data8 ");
      outdec(value);
      newline();
      return 0;
    case WORDr0:
      pcode_dumpzero(BPW, value);
      return 0;
    case BYTEr0:
      pcode_dumpzero(1, value);
      return 0;
    case WORD_:
    case BYTE_:
    case COMMAn:
    case NEARm:
      if(pcode_switch_mode) {
        pcode_switch_label = value;
        pcode_switch_have_label = 1;
        return 0;
        }
      return 0;
    case SWITCH:
      pcode_switch_mode = 1;
      pcode_switch_have_label = 0;
      return 0;
    }
  return pcode_unsupported(pcode);
  }

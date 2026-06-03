/*
** Host interpreter for the experimental Small-C external p-code.
**
** The input is textual p-code assembly emitted by smallcc --backend pcode.
** This tool encodes it into the compact 8-bit bytecode stream, then runs
** that bytecode with 16-bit stack cells.
*/

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_INSNS     16384
#define MAX_SYMBOLS    1024
#define MAX_NATIVES     256
#define MAX_CODE      65536
#define MAX_MEMORY    65536
#define MAX_STACK      4096
#define MAX_FRAMES      256
#define MAX_LOCALS     1024
#define MAX_LINE        512
#define MAX_NAME         64
#define MAX_UART       4096

#define SYM_CODE 1
#define SYM_DATA 2

#define IK_ICONST      1
#define IK_LLOCAL      2
#define IK_SLOCAL      3
#define IK_ADDR_LOCAL  4
#define IK_LGLOBAL     5
#define IK_SGLOBAL     6
#define IK_ADDR_GLOBAL 7
#define IK_LBYTE       8
#define IK_SBYTE       9
#define IK_LWORD      10
#define IK_SWORD      11
#define IK_ADD        12
#define IK_SUB        13
#define IK_AND        14
#define IK_OR         15
#define IK_XOR        16
#define IK_SHL        17
#define IK_SHR        18
#define IK_NEG        19
#define IK_BNOT       20
#define IK_LNOT       21
#define IK_EQ         22
#define IK_NE         23
#define IK_LT         24
#define IK_LE         25
#define IK_GT         26
#define IK_GE         27
#define IK_MUL        28
#define IK_UDIV       29
#define IK_UMOD       30
#define IK_SDIV       31
#define IK_SMOD       32
#define IK_JMP        33
#define IK_JZ         34
#define IK_JNZ        35
#define IK_CALL       36
#define IK_NCALL      37
#define IK_RET        38
#define IK_DROP       39
#define IK_DUP        40
#define IK_SWAP       41
#define IK_ENTER      42
#define IK_LEAVE      43
#define IK_NOP        44
#define IK_HALT       45
#define IK_ADDR_FUNC  46
#define IK_ICALL      47
#define IK_ADDI       48
#define IK_SUBI       49
#define IK_EQI        50
#define IK_ADDI_U16   51
#define IK_ZLOCAL     52

#define OP_NOP              0x00
#define OP_HALT             0x01
#define OP_ICONST_M1        0x02
#define OP_ICONST_0         0x03
#define OP_ICONST_1         0x04
#define OP_ICONST_2         0x05
#define OP_ICONST_S8        0x06
#define OP_ICONST_U16       0x07
#define OP_DROP             0x08
#define OP_DUP              0x09
#define OP_SWAP             0x0a
#define OP_ADDI_S8          0x0b
#define OP_SUBI_S8          0x0c
#define OP_EQI_S8           0x0d
#define OP_ADDI_U16         0x0e
#define OP_LLOCAL_0         0x10
#define OP_LLOCAL_1         0x11
#define OP_LLOCAL_2         0x12
#define OP_LLOCAL_3         0x13
#define OP_SLOCAL_0         0x14
#define OP_SLOCAL_1         0x15
#define OP_SLOCAL_2         0x16
#define OP_SLOCAL_3         0x17
#define OP_LLOCAL_S8        0x18
#define OP_SLOCAL_S8        0x19
#define OP_LLOCAL_U16       0x1a
#define OP_SLOCAL_U16       0x1b
#define OP_ADDR_LOCAL_S8    0x1c
#define OP_ADDR_LOCAL_U16   0x1d
#define OP_LGLOBAL_U16      0x20
#define OP_SGLOBAL_U16      0x21
#define OP_ADDR_GLOBAL_U16  0x22
#define OP_ZLOCAL_0         0x23
#define OP_ZLOCAL_1         0x24
#define OP_ZLOCAL_2         0x25
#define OP_ZLOCAL_3         0x26
#define OP_ZLOCAL_S8        0x27
#define OP_ZLOCAL_U16       0x28
#define OP_LBYTE            0x30
#define OP_SBYTE            0x31
#define OP_LWORD            0x32
#define OP_SWORD            0x33
#define OP_JMP_S8           0x40
#define OP_JMP_S16          0x41
#define OP_JZ_S8            0x42
#define OP_JZ_S16           0x43
#define OP_JNZ_S8           0x44
#define OP_JNZ_S16          0x45
#define OP_CALL_U16         0x50
#define OP_RET              0x51
#define OP_ENTER_U8         0x52
#define OP_ENTER_U16        0x53
#define OP_NCALL_U8         0x54
#define OP_NCALL_U16        0x55
#define OP_LEAVE            0x56
#define OP_ICALL_U8         0x57
#define OP_CALL0_U16        0x58
#define OP_CALL1_U16        0x59
#define OP_CALL2_U16        0x5a
#define OP_CALL3_U16        0x5e
#define OP_ADD              0x60
#define OP_SUB              0x61
#define OP_AND              0x62
#define OP_OR               0x63
#define OP_XOR              0x64
#define OP_SHL              0x65
#define OP_SHR              0x66
#define OP_NEG              0x67
#define OP_BNOT             0x68
#define OP_LNOT             0x69
#define OP_EQ               0x6a
#define OP_NE               0x6b
#define OP_LT               0x6c
#define OP_LE               0x6d
#define OP_GT               0x6e
#define OP_GE               0x6f
#define OP_MUL              0x70
#define OP_UDIV             0x71
#define OP_UMOD             0x72
#define OP_SDIV             0x73
#define OP_SMOD             0x74

struct Insn {
  int kind;
  int a;
  int b;
  int addr;
  int size;
  char name[MAX_NAME];
};

struct Symbol {
  char name[MAX_NAME];
  int kind;
  int index;
  int addr;
};

struct Frame {
  int ret_pc;
  int used;
  int off[MAX_LOCALS];
  int val[MAX_LOCALS];
};

static struct Insn insn[MAX_INSNS];
static int insn_count;
static struct Symbol symtab[MAX_SYMBOLS];
static int sym_count;
static char native_name[MAX_NATIVES][MAX_NAME];
static int native_count;
static unsigned char code[MAX_CODE];
static int code_size;
static unsigned char memory[MAX_MEMORY];
static int memory_size;
static unsigned short stack[MAX_STACK];
static int sp;
static struct Frame frames[MAX_FRAMES];
static int fp;
static char entry_name[MAX_NAME];
static int entry_pc;
static char uart_out[MAX_UART];
static int uart_len;
static char uart_in[MAX_UART];
static int uart_in_len;
static int uart_in_pos;
static int trace_flag;

static int fail(msg) char *msg; {
  fputs("pcinterp: ", stderr);
  fputs(msg, stderr);
  fputc('\n', stderr);
  return 1;
}

static int str_eq(a, b) char *a, *b; {
  return strcmp(a, b) == 0;
}

static int starts_name_char(ch) int ch; {
  return isalpha(ch) || ch == '_' || ch == '.';
}

static int name_char(ch) int ch; {
  return isalnum(ch) || ch == '_' || ch == '.';
}

static char *skip_ws(p) char *p; {
  while(*p && isspace((unsigned char)*p)) ++p;
  return p;
}

static void trim_line(p) char *p; {
  char *q;
  q = p;
  while(*q) {
    if(*q == ';') {
      *q = 0;
      break;
    }
    ++q;
  }
  q = p + strlen(p);
  while(q > p && isspace((unsigned char)q[-1])) {
    --q;
    *q = 0;
  }
}

static int next_token(pp, out) char **pp, *out; {
  char *p;
  int n;
  p = skip_ws(*pp);
  if(*p == 0) {
    *pp = p;
    out[0] = 0;
    return 0;
  }
  n = 0;
  while(*p && !isspace((unsigned char)*p)) {
    if(n < MAX_NAME - 1) out[n++] = *p;
    ++p;
  }
  out[n] = 0;
  *pp = p;
  return 1;
}

static int parse_int(s) char *s; {
  long v;
  v = strtol(s, 0, 0);
  return (int)v;
}

static int add_symbol(name, kind, index, addr) char *name; int kind, index, addr; {
  int i;
  for(i = 0; i < sym_count; ++i) {
    if(str_eq(symtab[i].name, name)) {
      symtab[i].kind = kind;
      symtab[i].index = index;
      symtab[i].addr = addr;
      return i;
    }
  }
  if(sym_count >= MAX_SYMBOLS) {
    fail("symbol table overflow");
    exit(1);
  }
  strncpy(symtab[sym_count].name, name, MAX_NAME - 1);
  symtab[sym_count].name[MAX_NAME - 1] = 0;
  symtab[sym_count].kind = kind;
  symtab[sym_count].index = index;
  symtab[sym_count].addr = addr;
  ++sym_count;
  return sym_count - 1;
}

static int find_symbol(name) char *name; {
  int i;
  for(i = 0; i < sym_count; ++i)
    if(str_eq(symtab[i].name, name)) return i;
  return -1;
}

static int symbol_addr(name, kind) char *name; int kind; {
  int i;
  i = find_symbol(name);
  if(i < 0 || symtab[i].kind != kind) {
    fputs("pcinterp: unknown symbol: ", stderr);
    fputs(name, stderr);
    fputc('\n', stderr);
    exit(1);
  }
  return symtab[i].addr;
}

static int native_id(name) char *name; {
  int i;
  for(i = 0; i < native_count; ++i)
    if(str_eq(native_name[i], name)) return i;
  if(native_count >= MAX_NATIVES) {
    fail("native table overflow");
    exit(1);
  }
  strncpy(native_name[native_count], name, MAX_NAME - 1);
  native_name[native_count][MAX_NAME - 1] = 0;
  ++native_count;
  return native_count - 1;
}

static void mem_append_byte(v) int v; {
  if(memory_size >= MAX_MEMORY) {
    fail("global memory overflow");
    exit(1);
  }
  memory[memory_size++] = (unsigned char)(v & 255);
}

static void add_insn(kind, a, b, name) int kind, a, b; char *name; {
  if(insn_count >= MAX_INSNS) {
    fail("instruction table overflow");
    exit(1);
  }
  insn[insn_count].kind = kind;
  insn[insn_count].a = a;
  insn[insn_count].b = b;
  insn[insn_count].addr = 0;
  insn[insn_count].size = 1;
  if(name) {
    strncpy(insn[insn_count].name, name, MAX_NAME - 1);
    insn[insn_count].name[MAX_NAME - 1] = 0;
  } else {
    insn[insn_count].name[0] = 0;
  }
  ++insn_count;
}

static int int16(v) int v; {
  v &= 0xffff;
  if(v & 0x8000) v -= 0x10000;
  return v;
}

static int local_size(kind, value) int kind, value; {
  if((kind == IK_LLOCAL || kind == IK_SLOCAL || kind == IK_ZLOCAL) && value >= 0 && value <= 3)
    return 1;
  if(value >= -128 && value <= 127) return 2;
  return 3;
}

static int insn_base_size(ip) struct Insn *ip; {
  int v;
  v = ip->a;
  switch(ip->kind) {
  case IK_ICONST:
    if(v == -1 || v == 0 || v == 1 || v == 2) return 1;
    if(v >= -128 && v <= 127) return 2;
    return 3;
  case IK_ADDI:
  case IK_SUBI:
  case IK_EQI:
    return 2;
  case IK_ADDI_U16:
    return 3;
  case IK_LLOCAL:
  case IK_SLOCAL:
  case IK_ZLOCAL:
  case IK_ADDR_LOCAL:
    return local_size(ip->kind, v);
  case IK_LGLOBAL:
  case IK_SGLOBAL:
  case IK_ADDR_GLOBAL:
    return 3;
  case IK_ADDR_FUNC:
    return 3;
  case IK_JMP:
  case IK_JZ:
  case IK_JNZ:
    return ip->size == 3 ? 3 : 2;
  case IK_CALL:
    if(v >= 0 && v <= 2) return 3;
    return 4;
  case IK_NCALL:
    if(native_id(ip->name) <= 255) return 3;
    return 4;
  case IK_ICALL:
    return 2;
  case IK_ENTER:
    if(v >= 0 && v <= 255) return 2;
    return 3;
  default:
    return 1;
  }
}

static void assign_addresses() {
  int i;
  int pc;
  int changed;
  int pass;
  int rel;
  int target;
  pc = 0;
  for(i = 0; i < insn_count; ++i) insn[i].size = insn_base_size(&insn[i]);
  for(pass = 0; pass < 8; ++pass) {
    pc = 0;
    for(i = 0; i < insn_count; ++i) {
      insn[i].addr = pc;
      pc += insn[i].size;
    }
    for(i = 0; i < sym_count; ++i) {
      if(symtab[i].kind == SYM_CODE) {
        if(symtab[i].index < insn_count) symtab[i].addr = insn[symtab[i].index].addr;
        else symtab[i].addr = pc;
      }
    }
    changed = 0;
    for(i = 0; i < insn_count; ++i) {
      if(insn[i].kind == IK_JMP || insn[i].kind == IK_JZ || insn[i].kind == IK_JNZ) {
        target = symbol_addr(insn[i].name, SYM_CODE);
        rel = target - (insn[i].addr + 2);
        if(rel >= -128 && rel <= 127) {
          if(insn[i].size != 2) changed = 1;
          insn[i].size = 2;
        } else {
          if(insn[i].size != 3) changed = 1;
          insn[i].size = 3;
        }
      } else {
        insn[i].size = insn_base_size(&insn[i]);
      }
    }
    if(!changed) break;
  }
  pc = 0;
  for(i = 0; i < insn_count; ++i) {
    insn[i].addr = pc;
    pc += insn[i].size;
  }
  for(i = 0; i < sym_count; ++i) {
    if(symtab[i].kind == SYM_CODE) {
      if(symtab[i].index < insn_count) symtab[i].addr = insn[symtab[i].index].addr;
      else symtab[i].addr = pc;
    }
  }
  code_size = pc;
}

static void emit8(v) int v; {
  if(code_size >= MAX_CODE) {
    fail("bytecode overflow");
    exit(1);
  }
  code[code_size++] = (unsigned char)(v & 255);
}

static void emit16(v) int v; {
  emit8(v);
  emit8(v >> 8);
}

static void encode_local(kind, value) int kind, value; {
  if(kind == IK_LLOCAL && value >= 0 && value <= 3) {
    emit8(OP_LLOCAL_0 + value);
    return;
  }
  if(kind == IK_SLOCAL && value >= 0 && value <= 3) {
    emit8(OP_SLOCAL_0 + value);
    return;
  }
  if(value >= -128 && value <= 127) {
    if(kind == IK_LLOCAL) emit8(OP_LLOCAL_S8);
    else if(kind == IK_SLOCAL) emit8(OP_SLOCAL_S8);
    else emit8(OP_ADDR_LOCAL_S8);
    emit8(value);
    return;
  }
  if(kind == IK_LLOCAL) emit8(OP_LLOCAL_U16);
  else if(kind == IK_SLOCAL) emit8(OP_SLOCAL_U16);
  else emit8(OP_ADDR_LOCAL_U16);
  emit16(value);
}

static void encode() {
  int i;
  int id;
  int rel;
  int target;
  int op;
  code_size = 0;
  for(i = 0; i < insn_count; ++i) {
    switch(insn[i].kind) {
    case IK_NOP: emit8(OP_NOP); break;
    case IK_HALT: emit8(OP_HALT); break;
    case IK_DROP: emit8(OP_DROP); break;
    case IK_DUP: emit8(OP_DUP); break;
    case IK_SWAP: emit8(OP_SWAP); break;
    case IK_ICONST:
      if(insn[i].a == -1) emit8(OP_ICONST_M1);
      else if(insn[i].a == 0) emit8(OP_ICONST_0);
      else if(insn[i].a == 1) emit8(OP_ICONST_1);
      else if(insn[i].a == 2) emit8(OP_ICONST_2);
      else if(insn[i].a >= -128 && insn[i].a <= 127) {
        emit8(OP_ICONST_S8);
        emit8(insn[i].a);
      } else {
        emit8(OP_ICONST_U16);
        emit16(insn[i].a);
      }
      break;
    case IK_ADDI:
      emit8(OP_ADDI_S8);
      emit8(insn[i].a);
      break;
    case IK_ADDI_U16:
      emit8(OP_ADDI_U16);
      emit16(insn[i].a);
      break;
    case IK_SUBI:
      emit8(OP_SUBI_S8);
      emit8(insn[i].a);
      break;
    case IK_EQI:
      emit8(OP_EQI_S8);
      emit8(insn[i].a);
      break;
    case IK_LLOCAL:
    case IK_SLOCAL:
    case IK_ADDR_LOCAL:
      encode_local(insn[i].kind, insn[i].a);
      break;
    case IK_ZLOCAL:
      if(insn[i].a >= 0 && insn[i].a <= 3) emit8(OP_ZLOCAL_0 + insn[i].a);
      else if(insn[i].a >= -128 && insn[i].a <= 127) {
        emit8(OP_ZLOCAL_S8);
        emit8(insn[i].a);
      } else {
        emit8(OP_ZLOCAL_U16);
        emit16(insn[i].a);
      }
      break;
    case IK_LGLOBAL:
      emit8(OP_LGLOBAL_U16);
      emit16(symbol_addr(insn[i].name, SYM_DATA));
      break;
    case IK_SGLOBAL:
      emit8(OP_SGLOBAL_U16);
      emit16(symbol_addr(insn[i].name, SYM_DATA));
      break;
    case IK_ADDR_GLOBAL:
      emit8(OP_ADDR_GLOBAL_U16);
      emit16(symbol_addr(insn[i].name, SYM_DATA));
      break;
    case IK_ADDR_FUNC:
      emit8(OP_ICONST_U16);
      emit16(symbol_addr(insn[i].name, SYM_CODE));
      break;
    case IK_LBYTE: emit8(OP_LBYTE); break;
    case IK_SBYTE: emit8(OP_SBYTE); break;
    case IK_LWORD: emit8(OP_LWORD); break;
    case IK_SWORD: emit8(OP_SWORD); break;
    case IK_ADD: emit8(OP_ADD); break;
    case IK_SUB: emit8(OP_SUB); break;
    case IK_AND: emit8(OP_AND); break;
    case IK_OR: emit8(OP_OR); break;
    case IK_XOR: emit8(OP_XOR); break;
    case IK_SHL: emit8(OP_SHL); break;
    case IK_SHR: emit8(OP_SHR); break;
    case IK_NEG: emit8(OP_NEG); break;
    case IK_BNOT: emit8(OP_BNOT); break;
    case IK_LNOT: emit8(OP_LNOT); break;
    case IK_EQ: emit8(OP_EQ); break;
    case IK_NE: emit8(OP_NE); break;
    case IK_LT: emit8(OP_LT); break;
    case IK_LE: emit8(OP_LE); break;
    case IK_GT: emit8(OP_GT); break;
    case IK_GE: emit8(OP_GE); break;
    case IK_MUL: emit8(OP_MUL); break;
    case IK_UDIV: emit8(OP_UDIV); break;
    case IK_UMOD: emit8(OP_UMOD); break;
    case IK_SDIV: emit8(OP_SDIV); break;
    case IK_SMOD: emit8(OP_SMOD); break;
    case IK_JMP:
    case IK_JZ:
    case IK_JNZ:
      target = symbol_addr(insn[i].name, SYM_CODE);
      if(insn[i].size == 2) {
        if(insn[i].kind == IK_JMP) op = OP_JMP_S8;
        else if(insn[i].kind == IK_JZ) op = OP_JZ_S8;
        else op = OP_JNZ_S8;
        rel = target - (insn[i].addr + 2);
        emit8(op);
        emit8(rel);
      } else {
        if(insn[i].kind == IK_JMP) op = OP_JMP_S16;
        else if(insn[i].kind == IK_JZ) op = OP_JZ_S16;
        else op = OP_JNZ_S16;
        rel = target - (insn[i].addr + 3);
        emit8(op);
        emit16(rel);
      }
      break;
    case IK_CALL:
      if(insn[i].a >= 0 && insn[i].a <= 3) {
        if(insn[i].a <= 2) emit8(OP_CALL0_U16 + insn[i].a);
        else emit8(OP_CALL3_U16);
        emit16(symbol_addr(insn[i].name, SYM_CODE));
      } else {
        emit8(OP_CALL_U16);
        emit16(symbol_addr(insn[i].name, SYM_CODE));
        emit8(insn[i].a);
      }
      break;
    case IK_NCALL:
      id = native_id(insn[i].name);
      if(id <= 255) {
        emit8(OP_NCALL_U8);
        emit8(id);
        emit8(insn[i].a);
      } else {
        emit8(OP_NCALL_U16);
        emit16(id);
        emit8(insn[i].a);
      }
      break;
    case IK_ICALL:
      emit8(OP_ICALL_U8);
      emit8(insn[i].a);
      break;
    case IK_RET:
      emit8(OP_RET);
      break;
    case IK_ENTER:
      if(insn[i].a >= 0 && insn[i].a <= 255) {
        emit8(OP_ENTER_U8);
        emit8(insn[i].a);
      } else {
        emit8(OP_ENTER_U16);
        emit16(insn[i].a);
      }
      break;
    case IK_LEAVE:
      emit8(OP_LEAVE);
      break;
    default:
      fail("internal encoder error");
      exit(1);
    }
  }
}

static int parse_kind(op) char *op; {
  if(str_eq(op, "nop")) return IK_NOP;
  if(str_eq(op, "halt")) return IK_HALT;
  if(str_eq(op, "drop")) return IK_DROP;
  if(str_eq(op, "dup")) return IK_DUP;
  if(str_eq(op, "swap")) return IK_SWAP;
  if(str_eq(op, "addi")) return IK_ADDI;
  if(str_eq(op, "addi_u16")) return IK_ADDI_U16;
  if(str_eq(op, "subi")) return IK_SUBI;
  if(str_eq(op, "eqi")) return IK_EQI;
  if(str_eq(op, "zlocal")) return IK_ZLOCAL;
  if(str_eq(op, "lbyte")) return IK_LBYTE;
  if(str_eq(op, "sbyte")) return IK_SBYTE;
  if(str_eq(op, "lword")) return IK_LWORD;
  if(str_eq(op, "sword")) return IK_SWORD;
  if(str_eq(op, "add")) return IK_ADD;
  if(str_eq(op, "sub")) return IK_SUB;
  if(str_eq(op, "and")) return IK_AND;
  if(str_eq(op, "or")) return IK_OR;
  if(str_eq(op, "xor")) return IK_XOR;
  if(str_eq(op, "shl")) return IK_SHL;
  if(str_eq(op, "shr")) return IK_SHR;
  if(str_eq(op, "neg")) return IK_NEG;
  if(str_eq(op, "bnot")) return IK_BNOT;
  if(str_eq(op, "lnot")) return IK_LNOT;
  if(str_eq(op, "eq")) return IK_EQ;
  if(str_eq(op, "ne")) return IK_NE;
  if(str_eq(op, "lt")) return IK_LT;
  if(str_eq(op, "le")) return IK_LE;
  if(str_eq(op, "gt")) return IK_GT;
  if(str_eq(op, "ge")) return IK_GE;
  if(str_eq(op, "mul")) return IK_MUL;
  if(str_eq(op, "udiv")) return IK_UDIV;
  if(str_eq(op, "umod")) return IK_UMOD;
  if(str_eq(op, "sdiv")) return IK_SDIV;
  if(str_eq(op, "smod")) return IK_SMOD;
  if(str_eq(op, "ret")) return IK_RET;
  if(str_eq(op, "leave")) return IK_LEAVE;
  return 0;
}

static void parse_data_values(p, size) char *p; int size; {
  char tok[MAX_NAME];
  int v;
  while(next_token(&p, tok)) {
    v = parse_int(tok);
    if(size == 1) mem_append_byte(v);
    else {
      mem_append_byte(v);
      mem_append_byte(v >> 8);
    }
  }
}

static int parse_file(path) char *path; {
  FILE *fp_in;
  char line[MAX_LINE];
  char op[MAX_NAME];
  char tok[MAX_NAME];
  char name[MAX_NAME];
  char *p;
  int v;
  int callkind;
  int line_no;
  fp_in = fopen(path, "r");
  if(!fp_in) return fail("cannot open input");
  line_no = 0;
  while(fgets(line, sizeof(line), fp_in)) {
    ++line_no;
    trim_line(line);
    p = skip_ws(line);
    if(*p == 0) continue;
    if(!next_token(&p, op)) continue;
    if(str_eq(op, "entry")) {
      if(!next_token(&p, entry_name)) return fail("entry without name");
      continue;
    }
    if(str_eq(op, "func") || str_eq(op, "static_func")) {
      if(!next_token(&p, tok)) return fail("func without name");
      add_symbol(tok, SYM_CODE, insn_count, 0);
      continue;
    }
    if(str_eq(op, "label")) {
      if(!next_token(&p, tok)) return fail("label without name");
      add_symbol(tok, SYM_CODE, insn_count, 0);
      continue;
    }
    if(str_eq(op, "data_label") || str_eq(op, "static_data_label")) {
      if(!next_token(&p, tok)) return fail("data_label without name");
      add_symbol(tok, SYM_DATA, 0, memory_size);
      continue;
    }
    if(str_eq(op, "data8")) {
      parse_data_values(p, 1);
      continue;
    }
    if(str_eq(op, "data16")) {
      parse_data_values(p, 2);
      continue;
    }
    if(str_eq(op, "zero")) {
      if(!next_token(&p, tok)) return fail("zero without count");
      v = parse_int(tok);
      while(v-- > 0) mem_append_byte(0);
      continue;
    }
    if(str_eq(op, "end")) break;
    if(str_eq(op, "iconst")) {
      if(!next_token(&p, tok)) return fail("iconst without value");
      add_insn(IK_ICONST, parse_int(tok), 0, 0);
      continue;
    }
    if(str_eq(op, "addi")) {
      if(!next_token(&p, tok)) return fail("addi without value");
      add_insn(IK_ADDI, parse_int(tok), 0, 0);
      continue;
    }
    if(str_eq(op, "addi_u16")) {
      if(!next_token(&p, tok)) return fail("addi_u16 without value");
      add_insn(IK_ADDI_U16, parse_int(tok), 0, 0);
      continue;
    }
    if(str_eq(op, "subi")) {
      if(!next_token(&p, tok)) return fail("subi without value");
      add_insn(IK_SUBI, parse_int(tok), 0, 0);
      continue;
    }
    if(str_eq(op, "eqi")) {
      if(!next_token(&p, tok)) return fail("eqi without value");
      add_insn(IK_EQI, parse_int(tok), 0, 0);
      continue;
    }
    if(str_eq(op, "llocal") || str_eq(op, "slocal") || str_eq(op, "addr_local")) {
      if(!next_token(&p, tok)) return fail("local op without offset");
      if(str_eq(op, "llocal")) add_insn(IK_LLOCAL, parse_int(tok), 0, 0);
      else if(str_eq(op, "slocal")) add_insn(IK_SLOCAL, parse_int(tok), 0, 0);
      else add_insn(IK_ADDR_LOCAL, parse_int(tok), 0, 0);
      continue;
    }
    if(str_eq(op, "zlocal")) {
      if(!next_token(&p, tok)) return fail("zlocal without offset");
      add_insn(IK_ZLOCAL, parse_int(tok), 0, 0);
      continue;
    }
    if(str_eq(op, "lglobal") || str_eq(op, "sglobal") || str_eq(op, "addr_global")) {
      if(!next_token(&p, tok)) return fail("global op without name");
      if(str_eq(op, "lglobal")) add_insn(IK_LGLOBAL, 0, 0, tok);
      else if(str_eq(op, "sglobal")) add_insn(IK_SGLOBAL, 0, 0, tok);
      else add_insn(IK_ADDR_GLOBAL, 0, 0, tok);
      continue;
    }
    if(str_eq(op, "addr_func")) {
      if(!next_token(&p, tok)) return fail("addr_func without name");
      add_insn(IK_ADDR_FUNC, 0, 0, tok);
      continue;
    }
    if(str_eq(op, "jmp") || str_eq(op, "jz") || str_eq(op, "jnz")) {
      if(!next_token(&p, tok)) return fail("branch without target");
      if(str_eq(op, "jmp")) add_insn(IK_JMP, 0, 0, tok);
      else if(str_eq(op, "jz")) add_insn(IK_JZ, 0, 0, tok);
      else add_insn(IK_JNZ, 0, 0, tok);
      continue;
    }
    if(str_eq(op, "call") || str_eq(op, "ncall")) {
      callkind = str_eq(op, "ncall");
      if(!next_token(&p, name)) return fail("call without target");
      if(!next_token(&p, tok)) return fail("call without argc");
      v = parse_int(tok);
      if(callkind) {
        native_id(name);
        add_insn(IK_NCALL, v, 0, name);
      } else {
        add_insn(IK_CALL, v, 0, name);
      }
      continue;
    }
    if(str_eq(op, "icall")) {
      if(!next_token(&p, tok)) return fail("icall without argc");
      add_insn(IK_ICALL, parse_int(tok), 0, 0);
      continue;
    }
    if(str_eq(op, "enter")) {
      if(!next_token(&p, tok)) return fail("enter without size");
      add_insn(IK_ENTER, parse_int(tok), 0, 0);
      continue;
    }
    v = parse_kind(op);
    if(v) {
      add_insn(v, 0, 0, 0);
      continue;
    }
    fprintf(stderr, "%s:%d: unsupported p-code op: %s\n", path, line_no, op);
    fclose(fp_in);
    return 1;
  }
  fclose(fp_in);
  assign_addresses();
  encode();
  v = find_symbol(entry_name[0] ? entry_name : "_main");
  if(v < 0 || symtab[v].kind != SYM_CODE) return fail("entry function not found");
  entry_pc = symtab[v].addr;
  return 0;
}

static void push(v) int v; {
  if(sp >= MAX_STACK) {
    fail("VM stack overflow");
    exit(1);
  }
  stack[sp++] = (unsigned short)(v & 0xffff);
}

static int pop() {
  if(sp <= 0) {
    fail("VM stack underflow");
    exit(1);
  }
  --sp;
  return stack[sp] & 0xffff;
}

static int frame_find(off, create) int off, create; {
  int i;
  for(i = 0; i < frames[fp].used; ++i)
    if(frames[fp].off[i] == off) return i;
  if(!create) return -1;
  if(frames[fp].used >= MAX_LOCALS) {
    fail("frame local table overflow");
    exit(1);
  }
  i = frames[fp].used++;
  frames[fp].off[i] = off;
  frames[fp].val[i] = 0;
  return i;
}

static int load_local(off) int off; {
  int i;
  i = frame_find(off, 0);
  if(i < 0) return 0;
  return frames[fp].val[i] & 0xffff;
}

static void store_local(off, val) int off, val; {
  int i;
  i = frame_find(off, 1);
  frames[fp].val[i] = val & 0xffff;
}

static int read8(pc) int *pc; {
  int v;
  if(*pc >= code_size) {
    fail("bytecode read past end");
    exit(1);
  }
  v = code[*pc];
  ++*pc;
  return v;
}

static int read16(pc) int *pc; {
  int lo;
  int hi;
  lo = read8(pc);
  hi = read8(pc);
  return lo | (hi << 8);
}

static int read_s8(pc) int *pc; {
  int v;
  v = read8(pc);
  if(v & 0x80) v -= 0x100;
  return v;
}

static int read_s16(pc) int *pc; {
  return int16(read16(pc));
}

static int mem_read8(addr) int addr; {
  int off;
  addr &= 0xffff;
  if(addr & 0x8000) {
    off = addr & 0x7fff;
    if(off & 0x4000) off -= 0x8000;
    return load_local(off) & 255;
  }
  return memory[addr] & 255;
}

static int mem_read16(addr) int addr; {
  int lo;
  int hi;
  int off;
  addr &= 0xffff;
  if(addr & 0x8000) {
    off = addr & 0x7fff;
    if(off & 0x4000) off -= 0x8000;
    return load_local(off);
  }
  lo = memory[addr] & 255;
  hi = memory[(addr + 1) & 0xffff] & 255;
  return lo | (hi << 8);
}

static void mem_write8(addr, val) int addr, val; {
  int off;
  int old;
  addr &= 0xffff;
  if(addr & 0x8000) {
    off = addr & 0x7fff;
    if(off & 0x4000) off -= 0x8000;
    old = load_local(off);
    old = (old & 0xff00) | (val & 255);
    store_local(off, old);
    return;
  }
  memory[addr] = (unsigned char)(val & 255);
  if(addr >= memory_size) memory_size = addr + 1;
}

static void mem_write16(addr, val) int addr, val; {
  int off;
  addr &= 0xffff;
  if(addr & 0x8000) {
    off = addr & 0x7fff;
    if(off & 0x4000) off -= 0x8000;
    store_local(off, val);
    return;
  }
  mem_write8(addr, val);
  mem_write8(addr + 1, val >> 8);
}

static void uart_append(ch) int ch; {
  if(uart_len < MAX_UART - 1) {
    uart_out[uart_len++] = (char)(ch & 255);
    uart_out[uart_len] = 0;
  }
}

static int native_call(id, argc) int id, argc; {
  int args[16];
  int i;
  int addr;
  int addr2;
  int n;
  int c;
  if(argc > 16) {
    fail("too many native arguments");
    exit(1);
  }
  for(i = argc - 1; i >= 0; --i) args[i] = pop();
  if(id < 0 || id >= native_count) {
    fail("bad native id");
    exit(1);
  }
  if(str_eq(native_name[id], "_strlen") || str_eq(native_name[id], "strlen")) {
    addr = args[0];
    n = 0;
    while(mem_read8(addr + n) != 0) ++n;
    return n;
  }
  if(str_eq(native_name[id], "_putchar") || str_eq(native_name[id], "putchar")) {
    c = args[0] & 255;
    uart_append(c);
    return c;
  }
  if(str_eq(native_name[id], "_puts") || str_eq(native_name[id], "puts")) {
    addr = args[0];
    while((c = mem_read8(addr++)) != 0) uart_append(c);
    uart_append('\n');
    return 0;
  }
  if(str_eq(native_name[id], "_strcpy") || str_eq(native_name[id], "strcpy")) {
    addr = args[0];
    addr2 = args[1];
    n = 0;
    do {
      c = mem_read8(addr2 + n);
      mem_write8(addr + n, c);
      ++n;
    } while(c != 0);
    return addr;
  }
  if(str_eq(native_name[id], "_getchar") || str_eq(native_name[id], "getchar")) {
    if(uart_in_pos >= uart_in_len) return 0xffff;
    return uart_in[uart_in_pos++] & 255;
  }
  if(str_eq(native_name[id], "_strcmp") || str_eq(native_name[id], "strcmp")) {
    addr = args[0];
    addr2 = args[1];
    while(mem_read8(addr) && mem_read8(addr) == mem_read8(addr2)) {
      ++addr;
      ++addr2;
    }
    return int16(mem_read8(addr) - mem_read8(addr2));
  }
  fprintf(stderr, "pcinterp: unsupported native call: %s\n", native_name[id]);
  exit(1);
  return 0;
}

static int bin_op(op, a, b) int op, a, b; {
  int sa;
  int sb;
  a &= 0xffff;
  b &= 0xffff;
  sa = int16(a);
  sb = int16(b);
  switch(op) {
  case OP_ADD: return a + b;
  case OP_SUB: return a - b;
  case OP_AND: return a & b;
  case OP_OR: return a | b;
  case OP_XOR: return a ^ b;
  case OP_SHL: return a << (b & 15);
  case OP_SHR: return a >> (b & 15);
  case OP_EQ: return a == b;
  case OP_NE: return a != b;
  case OP_LT: return sa < sb;
  case OP_LE: return sa <= sb;
  case OP_GT: return sa > sb;
  case OP_GE: return sa >= sb;
  case OP_MUL: return a * b;
  case OP_UDIV: return b == 0 ? 0xffff : a / b;
  case OP_UMOD: return b == 0 ? 0xffff : a % b;
  case OP_SDIV: return sb == 0 ? 0xffff : int16(sa / sb);
  case OP_SMOD: return sb == 0 ? 0xffff : int16(sa % sb);
  }
  fail("bad binary opcode");
  exit(1);
  return 0;
}

static int run_vm(max_steps, ret_out, steps_out) int max_steps, *ret_out, *steps_out; {
  int pc;
  int op;
  int a;
  int b;
  int off;
  int target;
  int argc;
  int id;
  int rel;
  int steps;
  pc = entry_pc;
  sp = 0;
  fp = 0;
  frames[0].ret_pc = -1;
  frames[0].used = 0;
  steps = 0;
  while(1) {
    if(steps >= max_steps) return fail("max steps exceeded");
    ++steps;
    op = read8(&pc);
    if(trace_flag) fprintf(stderr, "pc=%04x op=%02x sp=%d fp=%d\n", pc - 1, op, sp, fp);
    switch(op) {
    case OP_NOP:
      break;
    case OP_HALT:
      *ret_out = sp ? pop() : 0;
      *steps_out = steps;
      return 0;
    case OP_ICONST_M1: push(0xffff); break;
    case OP_ICONST_0: push(0); break;
    case OP_ICONST_1: push(1); break;
    case OP_ICONST_2: push(2); break;
    case OP_ICONST_S8: push(read_s8(&pc)); break;
    case OP_ICONST_U16: push(read16(&pc)); break;
    case OP_ADDI_S8: b = read_s8(&pc); a = pop(); push(a + b); break;
    case OP_SUBI_S8: b = read_s8(&pc); a = pop(); push(a - b); break;
    case OP_EQI_S8: b = read_s8(&pc); a = pop(); push((a & 0xffff) == (b & 0xffff)); break;
    case OP_ADDI_U16: b = read16(&pc); a = pop(); push(a + b); break;
    case OP_DROP: pop(); break;
    case OP_DUP: a = pop(); push(a); push(a); break;
    case OP_SWAP: a = pop(); b = pop(); push(a); push(b); break;
    case OP_LLOCAL_0: push(load_local(0)); break;
    case OP_LLOCAL_1: push(load_local(1)); break;
    case OP_LLOCAL_2: push(load_local(2)); break;
    case OP_LLOCAL_3: push(load_local(3)); break;
    case OP_SLOCAL_0: store_local(0, pop()); break;
    case OP_SLOCAL_1: store_local(1, pop()); break;
    case OP_SLOCAL_2: store_local(2, pop()); break;
    case OP_SLOCAL_3: store_local(3, pop()); break;
    case OP_ZLOCAL_0: store_local(0, 0); break;
    case OP_ZLOCAL_1: store_local(1, 0); break;
    case OP_ZLOCAL_2: store_local(2, 0); break;
    case OP_ZLOCAL_3: store_local(3, 0); break;
    case OP_ZLOCAL_S8: store_local(read_s8(&pc), 0); break;
    case OP_ZLOCAL_U16: store_local(read_s16(&pc), 0); break;
    case OP_LLOCAL_S8: push(load_local(read_s8(&pc))); break;
    case OP_SLOCAL_S8: store_local(read_s8(&pc), pop()); break;
    case OP_LLOCAL_U16: push(load_local(read_s16(&pc))); break;
    case OP_SLOCAL_U16: store_local(read_s16(&pc), pop()); break;
    case OP_ADDR_LOCAL_S8: push(0x8000 | (read_s8(&pc) & 0x7fff)); break;
    case OP_ADDR_LOCAL_U16: push(0x8000 | (read_s16(&pc) & 0x7fff)); break;
    case OP_LGLOBAL_U16: push(mem_read16(read16(&pc))); break;
    case OP_SGLOBAL_U16: off = read16(&pc); mem_write16(off, pop()); break;
    case OP_ADDR_GLOBAL_U16: push(read16(&pc)); break;
    case OP_LBYTE: push(mem_read8(pop())); break;
    case OP_SBYTE: b = pop(); a = pop(); mem_write8(a, b); break;
    case OP_LWORD: push(mem_read16(pop())); break;
    case OP_SWORD: b = pop(); a = pop(); mem_write16(a, b); break;
    case OP_JMP_S8: rel = read_s8(&pc); pc += rel; break;
    case OP_JMP_S16: rel = read_s16(&pc); pc += rel; break;
    case OP_JZ_S8: rel = read_s8(&pc); if(pop() == 0) pc += rel; break;
    case OP_JZ_S16: rel = read_s16(&pc); if(pop() == 0) pc += rel; break;
    case OP_JNZ_S8: rel = read_s8(&pc); if(pop() != 0) pc += rel; break;
    case OP_JNZ_S16: rel = read_s16(&pc); if(pop() != 0) pc += rel; break;
    case OP_CALL_U16:
      target = read16(&pc);
      argc = read8(&pc);
      if(fp + 1 >= MAX_FRAMES) return fail("call stack overflow");
      ++fp;
      frames[fp].ret_pc = pc;
      frames[fp].used = 0;
      for(a = 0; a < argc; ++a) store_local(4 + a * 2, pop());
      pc = target;
      break;
    case OP_CALL0_U16:
    case OP_CALL1_U16:
    case OP_CALL2_U16:
    case OP_CALL3_U16:
      target = read16(&pc);
      if(op == OP_CALL3_U16) argc = 3;
      else argc = op - OP_CALL0_U16;
      if(fp + 1 >= MAX_FRAMES) return fail("call stack overflow");
      ++fp;
      frames[fp].ret_pc = pc;
      frames[fp].used = 0;
      for(a = 0; a < argc; ++a) store_local(4 + a * 2, pop());
      pc = target;
      break;
    case OP_ICALL_U8:
      argc = read8(&pc);
      target = pop();
      if(target < 0 || target >= code_size) return fail("invalid indirect p-code call target");
      if(fp + 1 >= MAX_FRAMES) return fail("call stack overflow");
      ++fp;
      frames[fp].ret_pc = pc;
      frames[fp].used = 0;
      for(a = 0; a < argc; ++a) store_local(4 + a * 2, pop());
      pc = target;
      break;
    case OP_NCALL_U8:
      id = read8(&pc);
      argc = read8(&pc);
      push(native_call(id, argc));
      break;
    case OP_NCALL_U16:
      id = read16(&pc);
      argc = read8(&pc);
      push(native_call(id, argc));
      break;
    case OP_RET:
      a = sp ? pop() : 0;
      if(fp == 0) {
        *ret_out = a & 0xffff;
        *steps_out = steps;
        return 0;
      }
      pc = frames[fp].ret_pc;
      --fp;
      push(a);
      break;
    case OP_ENTER_U8:
      read8(&pc);
      break;
    case OP_ENTER_U16:
      read16(&pc);
      break;
    case OP_LEAVE:
      break;
    case OP_NEG:
      push(-pop());
      break;
    case OP_BNOT:
      push(~pop());
      break;
    case OP_LNOT:
      push(pop() == 0);
      break;
    default:
      if(op >= OP_ADD && op <= OP_SMOD) {
        b = pop();
        a = pop();
        push(bin_op(op, a, b));
      } else {
        fprintf(stderr, "pcinterp: bad opcode %02x at %04x\n", op, pc - 1);
        return 1;
      }
      break;
    }
  }
}

static void print_escaped(prefix, value, len) char *prefix, *value; int len; {
  int i;
  int ch;
  fputs(prefix, stdout);
  for(i = 0; i < len; ++i) {
    ch = value[i] & 255;
    if(ch == '\n') fputs("\\n", stdout);
    else if(ch == '\r') fputs("\\r", stdout);
    else if(ch == '\t') fputs("\\t", stdout);
    else if(ch == 0) fputs("\\0", stdout);
    else if(ch == '\\') fputs("\\\\", stdout);
    else if(ch < 32 || ch >= 127) fprintf(stdout, "\\x%02x", ch);
    else fputc(ch, stdout);
  }
  fputc('\n', stdout);
}

static int decode_escapes(src, dst, cap) char *src, *dst; int cap; {
  int i;
  int n;
  int ch;
  i = 0;
  n = 0;
  while(src[i]) {
    if(n >= cap - 1) break;
    ch = src[i++];
    if(ch == '\\') {
      ch = src[i++];
      if(ch == 'n') ch = '\n';
      else if(ch == 'r') ch = '\r';
      else if(ch == 't') ch = '\t';
      else if(ch == '0') ch = 0;
      else if(ch == '\\') ch = '\\';
    }
    dst[n++] = (char)ch;
  }
  dst[n] = 0;
  return n;
}

int main(argc, argv) int argc; char **argv; {
  char *input;
  int i;
  int max_steps;
  int ret;
  int steps;
  input = 0;
  max_steps = 1000000;
  trace_flag = 0;
  uart_in_len = 0;
  uart_in_pos = 0;
  for(i = 1; i < argc; ++i) {
    if(str_eq(argv[i], "--max-steps") && i + 1 < argc) {
      max_steps = atoi(argv[++i]);
    } else if(str_eq(argv[i], "--trace")) {
      trace_flag = 1;
    } else if(str_eq(argv[i], "--uart-rx") && i + 1 < argc) {
      uart_in_len = decode_escapes(argv[++i], uart_in, MAX_UART);
    } else if(!input) {
      input = argv[i];
    } else {
      return fail("usage: pcinterp [--max-steps N] [--trace] [--uart-rx TEXT] program.pca");
    }
  }
  if(!input) return fail("usage: pcinterp [--max-steps N] [--trace] [--uart-rx TEXT] program.pca");
  if(parse_file(input)) return 1;
  if(run_vm(max_steps, &ret, &steps)) return 1;
  printf("RET=%u\n", ret & 0xffff);
  printf("HALT=1\n");
  printf("STEPS=%d\n", steps);
  printf("BYTECODE_BYTES=%d\n", code_size);
  printf("GLOBAL_DATA_BYTES=%d\n", memory_size);
  printf("NATIVE_TABLE_BYTES=%d\n", native_count * 2);
  printf("PCODE_OBJECT_BYTES=%d\n", code_size + memory_size + native_count * 2);
  print_escaped("UART=", uart_out, uart_len);
  return 0;
}

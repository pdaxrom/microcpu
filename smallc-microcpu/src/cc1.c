/*
** Small-C Compiler -- Part 1 --  Top End.
** Copyright 1982, 1983, 1985, 1988 J. E. Hendrix
** All rights reserved.
*/

#include <stdio.h>
#include "notice.h"
#include "cc.h"
#include "host_compat.h"

/*
** miscellaneous storage
*/
int
  nogo,     /* disable goto statements? */
  noloc,    /* disable block locals? */
  opindex,  /* index to matched operator */
  opsize,   /* size of operator in characters */
  swactive, /* inside a switch? */
  swdefault,/* default label #, else 0 */
 *swnext,   /* address of next entry */
 *swend,    /* address of last entry */
 *stage,    /* staging buffer address */
 *wq,       /* while queue */
  argcs,    /* static argc */
 *argvs,    /* static argv */
 *wqptr,    /* ptr to next entry */
  litptr,   /* ptr to next entry */
  macptr,   /* macro buffer index */
  pptr,     /* ptr to parsing buffer */
  ch,       /* current character of input line */
  nch,      /* next character of input line */
  declared, /* # of local bytes to declare, -1 when declared */
  iflevel,  /* #if... nest level */
  skiplevel,/* level at which #if... skipping started */
  nxtlab,   /* next avail label # */
  litlab,   /* label # assigned to literal pool */
  csp,      /* compiler relative stk ptr */
  argstk,   /* function arg sp */
  argtop,   /* highest formal argument offset */
  ncmp,     /* # open compound statements */
  errflag,  /* true after 1st error in statement */
  eof,      /* true on final input eof */
  output,   /* fd for output file */
  files,    /* true if file list specified on cmd line */
  filearg,  /* cur file arg index */
  input   = EOF, /* fd for input file */
  input2  = EOF, /* fd for "#include" file */
  inclevel, /* active include nesting depth */
  incpath_count, /* number of include search paths */
  skip_count, /* number of argv indexes consumed by options */
  macro_param_count, /* next function-like macro parameter slot */
  include_open_count, /* number of include files opened */
  objectmode, /* emit object-file compatible assembly */
  pubclass, /* storage class of symbol currently being emitted */
  decltype2, /* full type from the most recent declarator */
  functype,  /* return type of next function */
  curtype,   /* return type of current function */
  funcclass, /* storage class of next function */
  usexpr  = YES, /* true if value of expression is used */
  ccode   = YES, /* true while parsing C code */
 *snext,    /* next addr in stage */
 *stail,    /* last addr of data in stage */
 *slast,    /* last addr in stage */
  listfp,   /* file pointer to list device */
  lastst,   /* last parsed statement type */
  oldseg;   /* current segment (0, DATASEG, CODESEG) */

char
  optimize, /* optimize output of staging buffer? */
  alarm,    /* audible alarm on errors? */
  monitor,  /* monitor function headers? */
  pause,    /* pause for operator on errors? */
 *symtab,   /* symbol table */
 *litq,     /* literal pool */
 *macn,     /* macro name buffer */
 *macq,     /* macro string buffer */
 *pline,    /* parsing buffer */
 *mline,    /* macro buffer */
 *line,     /* ptr to pline or mline */
 *lptr,     /* ptr to current character in "line" */
 *glbptr,   /* global symbol table */
 *locptr,   /* next local symbol table entry */
  quote[2] = {'"'}, /* literal string for '"' */
 *cptr,     /* work ptrs to any char buffer */
 *cptr2,
 *cptr3,
  msname[MACNAMESIZE],   /* macro symbol name */
  ssname[NAMESIZE];   /* static symbol name */

char
  typedef_name[MAXTYPEDEFS * NAMESIZE],
  struct_name[MAXSTRUCTS * NAMESIZE],
  field_name[MAXFIELDS * NAMESIZE];

int
  typedef_count,
  typedef_type[MAXTYPEDEFS],
  typedef_id[MAXTYPEDEFS],
  typedef_size[MAXTYPEDEFS],
  struct_count,
  struct_size[MAXSTRUCTS],
  struct_first[MAXSTRUCTS],
  struct_fields[MAXSTRUCTS],
  field_count,
  field_parent[MAXFIELDS],
  field_type[MAXFIELDS],
  field_id[MAXFIELDS],
  field_size[MAXFIELDS],
  field_offset[MAXFIELDS],
  incfile[MAXINCLUDE],
  skip_arg[MAXSKIPARGS],
  macro_argc[MACNBR],
  macro_argfirst[MACNBR];

char
  incpath[MAXINCPATHS * LINESIZE],
  incdir[(MAXINCLUDE + 1) * LINESIZE],
  macro_param_name[MAXMACPARAMS * MACNAMESIZE];

int skipconst();
int doargs2();
int contline();

int op[16] = {   /* p-codes of signed binary operators */
  OR12,                        /* level5 */
  XOR12,                       /* level6 */
  AND12,                       /* level7 */
  EQ12,   NE12,                /* level8 */
  LE12,   GE12,  LT12,  GT12,  /* level9 */
  ASR12,  ASL12,               /* level10 */
  ADD12,  SUB12,               /* level11 */
  MUL12, DIV12, MOD12          /* level12 */
  };

int op2[16] = {  /* p-codes of unsigned binary operators */
  OR12,                        /* level5 */
  XOR12,                       /* level6 */
  AND12,                       /* level7 */
  EQ12,   NE12,                /* level8 */
  LE12u,  GE12u, LT12u, GT12u, /* level9 */
  ASR12,  ASL12,               /* level10 */
  ADD12,  SUB12,               /* level11 */
  MUL12u, DIV12u, MOD12u       /* level12 */
  };

/*
** execution begins here
*/
int smallc_main(argc, argv)
  int argc, *argv; {
  fputs(VERSION, stderr);
  fputs(CRIGHT1, stderr);
  argcs   = argc;
  argvs   = argv;
  swnext  = calloc(SWTABSZ, sizeof(*swnext));
  swend   = swnext+(SWTABSZ-SWSIZ);
  stage   = calloc(STAGESIZE * 2 * BPW, sizeof(*stage));
  wqptr   =
  wq      = calloc(WQTABSZ, sizeof(*wq));
  litq    = calloc(LITABSZ, 1);
  macn    = calloc(MACNSIZE, 1);
  macq    = calloc(MACQSIZE, 1);
  pline   = calloc(LINESIZE, 1);
  mline   = calloc(LINESIZE, 1);
  slast   = stage+(STAGESIZE*2*BPW);
  symtab  = calloc((NUMLOCS*SYMAVG + NUMGLBS*SYMMAX), 1);
  locptr  = STARTLOC;
  glbptr  = STARTGLB;

  ask();          /* get user options */
  openfile();     /* and initial input file */
  preprocess();   /* fetch first line */
  header();       /* intro code */
  setcodes();     /* initialize code pointer array */
  parse();        /* process ALL input */
  trailer();      /* follow-up code */
  fclose(output); /* explicitly close output */
  return 0;
  }

#ifndef SMALLC_SELFHOST
#undef int
int main(int host_argc, char **host_argv)
{
  return (int)smallc_main((intptr_t)host_argc, (intptr_t *)host_argv);
}
#define int intptr_t
#else
int main(argc, argv)
  int argc, *argv; {
  return smallc_main(argc, argv);
  }
#endif

/******************** high level parsing *******************/

/*
** process all input text
**
** At this level, only static declarations,
**      defines, includes and function
**      definitions are legal...
*/
int parse() {
  int k;
  while (eof == 0) {
    if     (dostatic())          ;
    else if(k = typedfunc())     {if(k == 1) dofunction();}
    else if(amatch("extern", 6)) dodeclare(EXTERNAL);
    else if(doenum())            ;
    else if(dostruct())          ;
    else if(dotypedef())         ;
    else if(dodeclare(STATIC))   ;
    else if( match("#asm"))      doasm();
    else if( match("#include"))  doinclude();
    else if( match("#define"))   dodefine();
    else if( match("#undef"))    doundef();
    else                         {functype = INT; funcclass = STATIC; dofunction();}
    blanks();                 /* force eof if pending */
    }
  }

/*
** accept modern-looking typed function definitions such as:
**   int main()
**   unsigned int f(a)
**
** Small-C 2.2 normally treats these as declarations.  This lookahead consumes
** only the leading type token and leaves the parser at the function name.
*/
int typedfunc() {
  char *save_lptr, *p;
  int c, depth, k, save_ch, save_nch, type, id, sz;
  char fname[NAMESIZE], header[LINESIZE];
  save_lptr = lptr;
  save_ch = ch;
  save_nch = nch;
  if(astreq(lptr, "struct", 6)) {
    amatch("struct", 6);
    if(symname(fname)) {
      while(ch && ch <= ' ') gch();
      if(ch == '{') {
        lptr = save_lptr; ch = save_ch; nch = save_nch;
        return 0;
        }
      }
    lptr = save_lptr; ch = save_ch; nch = save_nch;
    }
  if(decltype(&type, &id, &sz) == 0) {
    return 0;
    }
  while(ch && ch <= ' ') gch();
  if(ch == 0) {
    lptr = save_lptr; ch = save_ch; nch = save_nch;
    return 0;
    }
  while(match("*")) {
    while(ch && ch <= ' ') gch();
    if(ch == 0) {
      lptr = save_lptr; ch = save_ch; nch = save_nch;
      return 0;
      }
    }
  p = lptr;
  while(*p && *p <= ' ') ++p;
  if(alpha(*p) == 0) {
    lptr = save_lptr; ch = save_ch; nch = save_nch;
    return 0;
    }
  k = 0;
  while(an(*p)) {
    if(k < NAMEMAX) fname[k++] = *p;
    ++p;
    }
  fname[k] = 0;
  while(*p && *p <= ' ') ++p;
  if(*p == '(') {
    depth = 1;
    ++p;
    while(*p && depth) {
      if(*p == '(') ++depth;
      else if(*p == ')') --depth;
      ++p;
      }
    while(*p && *p <= ' ') ++p;
    if(depth == 0 && *p != ';') {
      functype = type;
      if(funcclass != PRIVATE) funcclass = STATIC;
      return 1;
      }
    }
  else {
    lptr = save_lptr; ch = save_ch; nch = save_nch;
    return 0;
    }

  if(depth == 0) {
    lptr = save_lptr; ch = save_ch; nch = save_nch;
    return 0;
    }

  k = 0;
  depth = 0;
  p = lptr;
  while(1) {
    while(*p) {
      c = *p++;
      if(k < LINEMAX) header[k++] = c;
      if(c == '(') ++depth;
      else if(c == ')' && --depth == 0) break;
      }
    if(depth == 0) break;
    if(k < LINEMAX) header[k++] = ' ';
    preprocess();
    if(eof) break;
    p = lptr;
    }
  while(*p && *p <= ' ') ++p;
  while(*p == 0 && eof == 0) {
    preprocess();
    p = lptr;
    while(*p && *p <= ' ') ++p;
    }
  if(*p == '{') {
    if(k < LINEMAX) header[k++] = ' ';
    if(k < LINEMAX) header[k++] = '{';
    header[k] = 0;
    k = 0;
    while(header[k]) {
      pline[k] = header[k];
      ++k;
      }
    pline[k] = 0;
    line = pline;
    bump(0);
    functype = type;
    if(funcclass != PRIVATE) funcclass = STATIC;
    return 1;
    }
  if(*p == ';') {
    if(cptr = findglb(fname)) {
      if(cptr[IDENT] != FUNCTION) multidef(fname);
      }
    else addsym(fname, FUNCTION, type, 0, 0, &glbptr,
      funcclass == PRIVATE ? PRIVATE : AUTOEXT);
    kill();
    return 2;
    }
  lptr = save_lptr; ch = save_ch; nch = save_nch;
  return 0;
  }

/*
** skip a modern prototype argument list in a top-level declaration
*/
int skipprotoargs() {
  int depth;
  depth = 1;
  while(depth) {
    if(ch == 0) {
      if(eof) break;
      preprocess();
      continue;
      }
    if(match("(")) ++depth;
    else if(match(")")) --depth;
    else gch();
    }
  if(depth) error("no close paren");
  }

/*
** test for global declarations
*/
int dodeclare(class) int class; {
  int type, id, sz;
  if(decltype(&type, &id, &sz))   {contline(); declglb2(type, class, id);}
  else if(class == EXTERNAL)      declglb(INT, class);
  else return 0;
  ns();
  return 1;
  }

int contline() {
  while(ch && ch <= ' ') gch();
  while(ch == 0 && eof == 0) preprocess();
  }

int dostatic() {
  int k;
  if(amatch("static", 6) == 0) return 0;
  funcclass = PRIVATE;
  k = typedfunc();
  if(k == 1) {
    dofunction();
    return 1;
    }
  if(k == 2) {
    funcclass = STATIC;
    return 1;
    }
  if(dodeclare(PRIVATE)) {
    funcclass = STATIC;
    return 1;
    }
  error("bad static declaration");
  kill();
  funcclass = STATIC;
  return 1;
  }

/*
** parse typedef declarations for simple scalar/pointer aliases
*/
int dotypedef() {
  int type, id, sz, baseid;
  if(amatch("typedef", 7) == 0) return 0;
  if(decltype(&type, &id, &sz) == 0) {
    error("bad typedef type");
    skip();
    ns();
    return 1;
    }
  baseid = id;
  while(1) {
    if(endst()) break;
    decl2(type, ARRAY, &id, &sz, baseid);
    if(id == ARRAY) error("typedef arrays unsupported");
    else addtypedef(ssname, decltype2, id, sz);
    if(match(",") == 0) break;
    }
  ns();
  return 1;
  }

int addtypedef(sname, type, id, size)
  char *sname; int type, id, size; {
  int i, k;
  char *name;
  if(findtypedef(sname) >= 0 || findglb(sname)) {
    multidef(sname);
    return 0;
    }
  if(typedef_count >= MAXTYPEDEFS) {
    error("typedef table overflow");
    return 0;
    }
  i = typedef_count++;
  typedef_type[i] = type;
  typedef_id[i] = id;
  typedef_size[i] = size;
  name = typedef_name + i * NAMESIZE;
  k = 0;
  while(k < NAMESIZE) name[k++] = 0;
  k = 0;
  while(sname[k] && k < NAMEMAX) {
    name[k] = sname[k];
    ++k;
    }
  return 1;
  }

int findtypedef(sname) char *sname; {
  int i;
  i = 0;
  while(i < typedef_count) {
    if(astreq(sname, typedef_name + i * NAMESIZE, NAMEMAX)) return i;
    ++i;
    }
  return -1;
  }

int typedeftype(type, id, sz) int *type, *id, *sz; {
  char *save_lptr;
  int save_ch, save_nch, i;
  char name[NAMESIZE];
  save_lptr = lptr;
  save_ch = ch;
  save_nch = nch;
  if(symname(name)) {
    i = findtypedef(name);
    if(i >= 0) {
      *type = typedef_type[i];
      *id = typedef_id[i];
      *sz = typedef_size[i];
      skipconst();
      return 1;
      }
    }
  lptr = save_lptr;
  ch = save_ch;
  nch = save_nch;
  return 0;
  }

int skipconst() {
  int matched, k;
  matched = 0;
  while(1) {
    while(ch && ch <= ' ') gch();
    if(ch == 0) return matched;
    if((k = astreq(lptr, "const", 5)) == 0) return matched;
    bump(k);
    matched = 1;
    }
  }

/*
** parse a declaration base type.  id/sz describe the default declarator.
*/
int decltype(type, id, sz) int *type, *id, *sz; {
  int i;
  skipconst();
  if(amatch("unsigned", 8)) {
    skipconst();
    if(amatch("char", 4)) {*type = UCHR; *id = VARIABLE; *sz = 1;}
    else {amatch("int", 3); *type = UINT; *id = VARIABLE; *sz = BPW;}
    skipconst();
    return 1;
    }
  if(amatch("int", 3)) {
    *type = INT;
    *id = VARIABLE;
    *sz = BPW;
    skipconst();
    return 1;
    }
  if(amatch("char", 4)) {
    *type = UCHR;
    *id = VARIABLE;
    *sz = 1;
    skipconst();
    return 1;
    }
  if(amatch("void", 4)) {
    *type = VOID;
    *id = VARIABLE;
    *sz = 0;
    skipconst();
    return 1;
    }
  if(amatch("enum", 4)) {
    symname(ssname);
    *type = INT;
    *id = VARIABLE;
    *sz = BPW;
    skipconst();
    return 1;
    }
  if(amatch("struct", 6)) {
    if(symname(ssname) == 0) {
      illname();
      return 0;
      }
    i = findstruct(ssname);
    if(i < 0) {
      error("unknown struct");
      i = addstruct(ssname);
      }
    *type = STRUCTBASE + i;
    *id = VARIABLE;
    *sz = struct_size[i];
    skipconst();
    return 1;
    }
  return typedeftype(type, id, sz);
  }

/*
** parse a named struct declaration and compute field layout
*/
int dostruct() {
  char *save_lptr;
  int save_ch, save_nch, type, id, sz, off, sidx, fid, baseid;
  save_lptr = lptr;
  save_ch = ch;
  save_nch = nch;
  if(amatch("struct", 6) == 0) return 0;
  if(symname(ssname) == 0) {
    lptr = save_lptr;
    ch = save_ch;
    nch = save_nch;
    return 0;
    }
  if(match("{") == 0) {
    lptr = save_lptr;
    ch = save_ch;
    nch = save_nch;
    return 0;
    }
  sidx = findstruct(ssname);
  if(sidx < 0) sidx = addstruct(ssname);
  struct_first[sidx] = field_count;
  struct_fields[sidx] = 0;
  off = 0;
  while(match("}") == 0) {
    if(decltype(&type, &id, &sz) == 0) {
      error("bad struct field type");
      skip();
      ns();
      continue;
      }
    baseid = id;
    while(1) {
      decl2(type, ARRAY, &id, &sz, baseid);
      type = decltype2;
      if(id == ARRAY) error("struct field arrays unsupported");
      off = alignup(off, typealign(type, id));
      fid = addfield(sidx, ssname, type, id, sz, off);
      if(fid >= 0) {
        off += sz;
        struct_fields[sidx] += 1;
        }
      if(match(",") == 0) break;
      }
    ns();
    }
  struct_size[sidx] = alignup(off, 2);
  ns();
  return 1;
  }

int findstruct(sname) char *sname; {
  int i;
  i = 0;
  while(i < struct_count) {
    if(astreq(sname, struct_name + i * NAMESIZE, NAMEMAX)) return i;
    ++i;
    }
  return -1;
  }

int addstruct(sname) char *sname; {
  int i, k;
  char *name;
  if(struct_count >= MAXSTRUCTS) {
    error("struct table overflow");
    return 0;
    }
  i = struct_count++;
  struct_size[i] = 0;
  struct_first[i] = field_count;
  struct_fields[i] = 0;
  name = struct_name + i * NAMESIZE;
  k = 0;
  while(k < NAMESIZE) name[k++] = 0;
  k = 0;
  while(sname[k] && k < NAMEMAX) {
    name[k] = sname[k];
    ++k;
    }
  return i;
  }

int isstruct(type) int type; {
  return (type >= STRUCTBASE && type < STRUCTBASE + MAXSTRUCTS);
  }

int structidx(type) int type; {
  return type - STRUCTBASE;
  }

int isptrtype(type) int type; {
  return type >= PTRBASE;
  }

int makeptrtype(type) int type; {
  return PTRBASE + type;
  }

int ptrbasetype(type) int type; {
  if(isptrtype(type)) return type - PTRBASE;
  return 0;
  }

int ptrtype(type, levels) int type, levels; {
  while(levels-- > 0) type = makeptrtype(type);
  return type;
  }

int typesize(type, id) int type, id; {
  int i;
  if(id == POINTER) return BPW;
  if(isptrtype(type)) return BPW;
  if(isstruct(type)) {
    i = structidx(type);
    if(i >= 0 && i < struct_count) return struct_size[i];
    }
  return type >> 2;
  }

int typealign(type, id) int type, id; {
  if(id == POINTER) return 2;
  if(isptrtype(type)) return 2;
  if(isstruct(type)) return 2;
  if((type >> 2) >= BPW) return 2;
  return 1;
  }

int alignup(value, align) int value, align; {
  if(align <= 1) return value;
  return (value + align - 1) & ~(align - 1);
  }

int addfield(parent, sname, type, id, size, offset)
  int parent, type, id, size, offset; char *sname; {
  int i, k;
  char *name;
  if(findfield(parent, sname) >= 0) {
    multidef(sname);
    return -1;
    }
  if(field_count >= MAXFIELDS) {
    error("field table overflow");
    return -1;
    }
  i = field_count++;
  field_parent[i] = parent;
  field_type[i] = type;
  field_id[i] = id;
  field_size[i] = size;
  field_offset[i] = offset;
  name = field_name + i * NAMESIZE;
  k = 0;
  while(k < NAMESIZE) name[k++] = 0;
  k = 0;
  while(sname[k] && k < NAMEMAX) {
    name[k] = sname[k];
    ++k;
    }
  return i;
  }

int findfield(parent, sname) int parent; char *sname; {
  int i, end;
  if(parent < 0 || parent >= struct_count) return -1;
  i = struct_first[parent];
  end = i + struct_fields[parent];
  while(i < end) {
    if(astreq(sname, field_name + i * NAMESIZE, NAMEMAX)) return i;
    ++i;
    }
  return -1;
  }

int fieldtype(i) int i; {return field_type[i];}
int fieldid(i) int i; {return field_id[i];}
int fieldsize(i) int i; {return field_size[i];}
int fieldoff(i) int i; {return field_offset[i];}
int structsize(i) int i; {return struct_size[i];}

/*
** declare a static variable
*/
int declglb(type, class)  int type, class; {
  declglb2(type, class, VARIABLE);
  }

int declglb2(type, class, baseid)  int type, class, baseid; {
  int id, dim, stars, levels, dtype, size;
  char *ptr;
  while(1) {
    contline();
    if(endst()) return;  /* do line */
    stars = 0;
    skipconst();
    while(match("*")) {
      ++stars;
      skipconst();
      }
    levels = stars;
    if(baseid == POINTER) ++levels;
    if(levels) {
      id = POINTER;
      dtype = ptrtype(type, levels - 1);
      dim = 0;
      }
    else {
      id = baseid;
      dtype = type;
      dim = 1;
      }
    if(symname(ssname) == 0) illname();
    if(match("(")) {
      id = FUNCTION;
      skipprotoargs();
      ptr = findglb(ssname);
      if(ptr) {
        if(ptr[IDENT] != FUNCTION) multidef(ssname);
        }
      else addsym(ssname, FUNCTION, type, 0, 0, &glbptr, AUTOEXT);
      if(match(",") == 0) return;
      continue;
      }
    ptr = findglb(ssname);
    if(ptr) {
      if(class == EXTERNAL && ptr[CLASS] == EXTERNAL) ;
      else if(ptr[CLASS] == EXTERNAL && class != EXTERNAL) {
        ptr[CLASS] = class;
        ptr[TYPE] = dtype;
        ptr[IDENT] = id;
        }
      else multidef(ssname);
      }
    if(match("[")) {
      id = ARRAY;
      dim = needsub();
      if(levels) dtype = ptrtype(type, levels);
      }
    if(type == VOID && id != POINTER) {
      error("void object");
      dtype = type = INT;
      dim = 1;
      }
    size = typesize(dtype, id);
    if(ptr && ptr[CLASS] == class) putint(id == POINTER ? BPW : dim * typesize(dtype, VARIABLE), ptr + SIZE, 2);
    if     (class == EXTERNAL) {
      if(objectmode == 0) external(ssname, size, id);
      }
    else if(   id != FUNCTION) {
      pubclass = class;
      initials(size, id, dim);
      if(id == ARRAY && dim == 0)
        dim = litptr / typesize(dtype, VARIABLE);
      }
    if(ptr == 0) {
      if(id == POINTER)
           addsym(ssname, id, dtype, BPW, 0, &glbptr, class);
      else addsym(ssname, id, dtype, dim * typesize(dtype, VARIABLE), 0, &glbptr, class);
      }
    if(match(",") == 0) return;
    contline();
    }
  }

/*
** initialize global objects
*/
int initials(size, ident, dim) int size, ident, dim; {
  int savedim;
  litptr = 0;
  if(dim == 0) dim = -1;         /* *... or ...[] */
  savedim = dim;
  public(ident);
  if(match("=")) {
    if(match("{")) {
      while(dim) {
        contline();
        if(match("}")) goto initdone;
        init(size, ident, &dim);
        contline();
        if(match(",") == 0) break;
        }
      need("}");
initdone:
      ;
      }
    else init(size, ident, &dim);
    }
  if(savedim == -1 && dim == -1) {
    if(ident == ARRAY) error("need array size");
    stowlit(0, size = BPW);
    }
  dumplits(size);
  dumpzero(size, dim);           /* only if dim > 0 */
  }

/*
** evaluate one initializer
*/
int init(size, ident, dim) int size, ident, *dim; {
  int value;
  contline();
  if(string(&value)) {
    if(ident == VARIABLE || size != 1)
      error("must assign to char pointer or char array");
    *dim -= (litptr - value);
    if(ident == POINTER) point();
    }
  else if(constexpr(&value)) {
    if(ident == POINTER) error("cannot assign to pointer");
    stowlit(value, size);
    *dim -= 1;
    }
  }

/*
** get required array size
*/
int needsub()  {
  int val;
  if(match("]")) return 0; /* null size */
  if(constexpr(&val) == 0) val = 1;
  if(val < 0) {
    error("negative size illegal");
    val = -val;
    }
  need("]");               /* force single dimension */
  return val;              /* and return size */
  }

/*
** open an include file
*/
int doinclude() {
  int i, quoted; char str[LINESIZE];
  blanks();       /* skip over to name */
  quoted = (*lptr == '"');
  if(*lptr == '"' || *lptr == '<') ++lptr;
  i = 0;
  while(lptr[i]
     && lptr[i] != '"'
     && lptr[i] != '>'
     && lptr[i] != '\n'
     && i < LINEMAX) {
    str[i] = lptr[i];
    ++i;
    }
  str[i] = NULL;
  openinclude(str, quoted);
  kill();   /* make next read come from new file (if open) */
  }

/*
** define a macro symbol
*/
int dodefine() {
  int k, idx, argc, first;
  if(macsymname(msname) == 0) {
    illname();
    kill();
    return;
    }
  k = 0;
  if(macsearch(msname) == 0) {
    if(cptr2 = cptr)
      while(*cptr2++ = msname[k++]) ;
    else {
      error("macro name table full");
      return;
      }
    }
  idx = macindex(cptr);
  macro_argc[idx] = -1;
  macro_argfirst[idx] = 0;
  if(ch == '(') {
    first = macro_param_count;
    argc = 0;
    bump(1);
    blanks();
    if(match(")") == 0) {
      while(1) {
        if(macsymname(msname) == 0) {
          illname();
          break;
          }
        if(argc >= MAXMACARGS) error("too many macro parameters");
        else addmacparam(msname);
        ++argc;
        blanks();
        if(match(")")) break;
        need(",");
        }
      }
    macro_argc[idx] = argc;
    macro_argfirst[idx] = first;
    }
  putint(macptr, cptr+MACNAMESIZE, 2);
  while(white()) gch();
  while(ch) {
    if(ch == '/' && nch == '*') {
      bump(2);
      while(ch && (ch == '*' && nch == '/') == 0) gch();
      if(ch) bump(2);
      }
    else if(macro_argc[idx] >= 0 && ch == '#') {
      if(nch == '#') error("unsupported macro token paste");
      else           error("unsupported macro stringification");
      gch();
      }
    else putmac(gch());
    }
  putmac(NULL);
  if(macptr >= MACMAX) {
    error("macro string queue full");
    abort(ERRCODE);
    }
  }

int defarg(text) char *text; {
  int i, j;
  char name[MACNAMESIZE], value[LINESIZE];
  i = 0;
  while(text[i] && text[i] != '=' && text[i] > ' ' && i < MACNAMEMAX) {
    name[i] = text[i];
    ++i;
    }
  name[i] = 0;
  if(name[0] == 0) {
    error("bad -D macro name");
    return 0;
    }
  if(text[i] == '=') {
    ++i;
    j = 0;
    while(text[i] && j < LINEMAX) value[j++] = text[i++];
    value[j] = 0;
    }
  else {
    value[0] = '1';
    value[1] = 0;
    }
  return addobjectmacro(name, value);
  }

int addobjectmacro(sname, value) char *sname, *value; {
  int k, idx;
  k = 0;
  if(macsearch(sname) == 0) {
    if(cptr2 = cptr)
      while(*cptr2++ = sname[k++]) ;
    else {
      error("macro name table full");
      return 0;
      }
    }
  idx = macindex(cptr);
  macro_argc[idx] = -1;
  macro_argfirst[idx] = 0;
  putint(macptr, cptr+MACNAMESIZE, 2);
  while(*value) putmac(*value++);
  putmac(NULL);
  if(macptr >= MACMAX) {
    error("macro string queue full");
    abort(ERRCODE);
    }
  return 1;
  }

int doundef() {
  if(macsymname(msname) == 0) {
    illname();
    kill();
    return;
    }
  if(macsearch(msname))
    *cptr = 1;
  kill();
  }

int putmac(c)  char c; {
  macq[macptr] = c;
  if(macptr < MACMAX) ++macptr;
  return c;
  }

int macindex(ptr) char *ptr; {
  return (ptr - macn) / MACENTRY;
  }

int addmacparam(sname) char *sname; {
  int i;
  char *dst;
  if(macro_param_count >= MAXMACPARAMS) {
    error("macro parameter table full");
    return 0;
    }
  dst = macro_param_name + macro_param_count * MACNAMESIZE;
  i = 0;
  while(i < MACNAMESIZE) dst[i++] = 0;
  i = 0;
  while(sname[i] && i < MACNAMEMAX) {
    dst[i] = sname[i];
    ++i;
    }
  ++macro_param_count;
  return 1;
  }

/*
** parse a simple enum declaration and install constants as int symbols
*/
int doenum() {
  int value;
  int hasvalue;
  if(amatch("enum", 4) == 0) return 0;
  symname(ssname);                 /* optional tag, currently informational */
  if(match("{")) {
    value = 0;
    while(match("}") == 0) {
      if(symname(ssname) == 0) {
        illname();
        break;
        }
      hasvalue = value;
      if(match("=")) constexpr(&hasvalue);
      addenum(ssname, hasvalue);
      value = hasvalue + 1;
      if(match(",")) {
        if(streq(lptr, "}")) continue;
        }
      else need("}");
      }
    }
  ns();
  return 1;
  }

/*
** add an enum constant to the ordinary global identifier namespace
*/
int addenum(sname, value) char *sname; int value; {
  if(findglb(sname)) {
    multidef(sname);
    return 0;
    }
  addsym(sname, ENUMCONST, INT, 0, value, &glbptr, STATIC);
  return 1;
  }

/*
** parse an optional argument type in an ANSI-style function header
*/
int argtype(type) int *type; {
  int id, sz;
  if(amatch("unsigned", 8)) {
    if(amatch("char", 4)) *type = UCHR;
    else {amatch("int", 3); *type = UINT;}
    return 1;
    }
  if(amatch("int", 3)) {
    *type = INT;
    return 1;
    }
  if(amatch("char", 4)) {
    *type = UCHR;
    return 1;
    }
  if(amatch("void", 4)) {
    *type = VOID;
    return 1;
    }
  if(typedeftype(type, &id, &sz)) return 1;
  return 0;
  }

/*
** begin a function
**
** called from "parse" and tries to make a function
** out of the following text
*/
int dofunction()  {
  int argcount, id, rettype, sz, type, typedargs;
  char *argptr[NUMLOCS], *ptr;
  nogo   =                      /* enable goto statements */
  noloc  =                      /* enable block-local declarations */
  lastst =                      /* no statement yet */
  litptr = 0;                   /* clear lit pool */
  litlab = getlabel();          /* label next lit pool */
  locptr = STARTLOC;            /* clear local variables */
  rettype = functype;
  if(match("void")) {rettype = VOID; blanks();}   /* old direct path */
  curtype = rettype;
  if(monitor) lout(line, stderr);
  if(symname(ssname) == 0) {
    error("illegal function or declaration");
    errflag = 0;
    kill();                     /* invalidate line */
    return;
    }
  if(ptr = findglb(ssname)) {   /* already in symbol table? */
    if(ptr[IDENT] != FUNCTION)
         multidef(ssname);
    else if(ptr[CLASS] == AUTOEXT) {
         ptr[CLASS] = funcclass;
         ptr[TYPE] = rettype;
         }
    else if(ptr[CLASS] == PRIVATE && funcclass == PRIVATE)
         ptr[TYPE] = rettype;
    else multidef(ssname);
    }
  else addsym(ssname, FUNCTION, rettype, 0, 0, &glbptr, funcclass);
  pubclass = funcclass;
  public(FUNCTION);
  argstk = 0;                  /* init arg count */
  argcount = typedargs = 0;
  if(match("(") == 0) error("no open paren");
  while(match(")") == 0) {     /* then count args */
    type = 0;
    if(streq(lptr, "void")) {
      char *save_lptr;
      int save_ch, save_nch;
      save_lptr = lptr;
      save_ch = ch;
      save_nch = nch;
      match("void");
      blanks();
      if(streq(lptr, ")")) {
        need(")");
        break;
        }
      lptr = save_lptr;
      ch = save_ch;
      nch = save_nch;
      }
    if(decltype(&type, &id, &sz)) {
      typedargs = YES;
      decl2(type, POINTER, &id, &sz, id);
      type = decltype2;
      if(type == VOID && id != POINTER) error("void argument");
      if(ssname[0]) {
        if(findloc(ssname)) multidef(ssname);
        else if(argcount < NUMLOCS) {
          argptr[argcount++] =
            addsym(ssname, id, type, sz, argstk, &locptr, AUTOMATIC);
          argstk += BPW;
          }
        else error("too many arguments");
        }
      else {
        error("illegal argument name");
        skip();
        }
      }
    else if(symname(ssname)) {
      if(findloc(ssname)) multidef(ssname);
      else {
        if(argcount < NUMLOCS)
          argptr[argcount++] =
            addsym(ssname, 0, 0, 0, argstk, &locptr, AUTOMATIC);
        else error("too many arguments");
        argstk += BPW;
        }
      }
    else {
      error("illegal argument name");
      skip();
      }
    blanks();
    if(streq(lptr,")") == 0 && match(",") == 0)
      error("no comma");
    if(endst()) break;
    }
  csp = 0;                     /* preset stack ptr */
  argtop = argstk+BPW;         /* account for the pushed BP */
  if(typedargs) {
    while(argcount) {
      ptr = argptr[--argcount];
      putint(argtop-getint(ptr+OFFSET, 2), ptr+OFFSET, 2);
      }
    argstk = 0;
    }
  while(argstk) {
    type = id = sz = 0;
    if     (amatch("char",     4)) {doargs(UCHR); ns();}
    else if(amatch("int",      3)) {doargs(INT);  ns();}
    else if(amatch("unsigned", 8)) {
      if   (amatch("char", 4))     {doargs(UCHR); ns();}
      else {amatch("int", 3);       doargs(UINT); ns();}
      }
    else if(decltype(&type, &id, &sz)) {doargs2(type, id); ns();}
    else {error("wrong number of arguments"); break;}
    }
  gen(ENTER, 0);
  statement();
  if(lastst != STRETURN && lastst != STGOTO)
    gen(RETURN, 0);
  if(litptr) {
    toseg(DATASEG);
    gen(REFm, litlab);
    dumplits(1);               /* dump literals */
    }
  functype = INT;
  curtype = INT;
  funcclass = STATIC;
  }

/*
** declare argument types
*/
int doargs(type) int type; {
  return doargs2(type, VARIABLE);
  }

int doargs2(type, baseid) int type, baseid; {
  int id, sz;
  char c, *ptr;
  while(1) {
    if(argstk == 0) return;           /* no arguments */
    if(decl2(type, POINTER, &id, &sz, baseid)) {
      if(ptr = findloc(ssname)) {
        ptr[IDENT] = id;
        ptr[TYPE]  = decltype2;
        putint(sz, ptr+SIZE, 2);
        putint(argtop-getint(ptr+OFFSET, 2), ptr+OFFSET, 2);
        }
      else error("not an argument");
      }
    argstk = argstk - BPW;            /* cnt down */
    if(endst()) return;
    if(match(",") == 0) error("no comma");
    }
  }

/*
** parse next local or argument declaration
*/
int decl(type, aid, id, sz) int type, aid, *id, *sz; {
  return decl2(type, aid, id, sz, VARIABLE);
  }

int decl2(type, aid, id, sz, baseid) int type, aid, *id, *sz, baseid; {
  int n, p, stars, levels, dim;
  if(match("(")) p = 1;
  else           p = 0;
  stars = 0;
  skipconst();
  while(match("*")) {
    ++stars;
    skipconst();
    }
  levels = stars;
  if(baseid == POINTER) ++levels;
  if(levels) {
    *id = POINTER;
    decltype2 = ptrtype(type, levels - 1);
    *sz = BPW;
    }
  else {
    *id = baseid;
    decltype2 = type;
    *sz = typesize(type, VARIABLE);
    }
  if((n = symname(ssname)) == 0) illname();
  if(p && match(")")) ;
  if(match("(")) {
    if(!p || *id != POINTER) error("try (*...)()");
    need(")");
    }
  else if(match("[")) {
    dim = needsub();
    if(levels) decltype2 = ptrtype(type, levels);
    *id = aid;
    *sz = typesize(decltype2, VARIABLE);
    if((*sz *= dim) == 0) {
      if(aid == ARRAY) error("need array size");
      *sz  = BPW;      /* size of pointer argument */
      }
    }
  return n;
  }

/******************** start 2nd level parsing *******************/

/*
** statement parser
*/
int statement() {
  int type, id, sz;
  if(ch == 0 && eof) return;
  else if(amatch("char",     4)) {declloc(UCHR);   ns();}
  else if(amatch("int",      3)) {declloc(INT);    ns();}
  else if(amatch("unsigned", 8)) {
    if   (amatch("char",     4)) {declloc(UCHR);   ns();}
    else {amatch("int",      3);  declloc(UINT);   ns();}
    }
  else if(decltype(&type, &id, &sz)) {declloc2(type, id); ns();}
  else {
    if(declared >= 0) {
      if(ncmp > 1) nogo = declared;   /* disable goto */
      gen(ADDSP, csp - declared);
      declared = -1;
      }
    if(match("{"))                 compound();
    else if(amatch("if",       2)) {doif();           lastst = STIF;}
    else if(amatch("while",    5)) {dowhile();        lastst = STWHILE;}
    else if(amatch("do",       2)) {dodo();           lastst = STDO;}
    else if(amatch("for",      3)) {dofor();          lastst = STFOR;}
    else if(amatch("switch",   6)) {doswitch();       lastst = STSWITCH;}
    else if(amatch("case",     4)) {docase();         lastst = STCASE;}
    else if(amatch("default",  7)) {dodefault();      lastst = STDEF;}
    else if(amatch("goto",     4)) {dogoto();         lastst = STGOTO;}
    else if(dolabel())                                lastst = STLABEL;
    else if(amatch("return",   6)) {doreturn(); ns(); lastst = STRETURN;}
    else if(amatch("break",    5)) {dobreak();  ns(); lastst = STBREAK;}
    else if(amatch("continue", 8)) {docont();   ns(); lastst = STCONT;}
    else if(match(";"))            errflag = 0;
    else if(match("#asm"))         {doasm();          lastst = STASM;}
    else                           {doexpr(NO); ns(); lastst = STEXPR;}
    }
  return lastst;
  }

/*
** declare local variables
*/
int declloc(type)  int type;  {
  declloc2(type, VARIABLE);
  }

int declloc2(type, baseid)  int type, baseid;  {
  int id, sz;
  if(swactive)     error("not allowed in switch");
  if(noloc)        error("not allowed with goto");
  if(declared < 0) error("must declare first in block");
  while(1) {
    if(endst()) return;
    decl2(type, ARRAY, &id, &sz, baseid);
    if(type == VOID && id != POINTER) error("void object");
    else {
      declared += sz;
      addsym(ssname, id, decltype2,  sz, csp - declared, &locptr, AUTOMATIC);
      }
    if(match(",") == 0) return;
    }
  }

int compound()  {
  int savcsp;
  char *savloc;
  savcsp = csp;
  savloc = locptr;
  declared = 0;           /* may now declare local variables */
  ++ncmp;                 /* new level open */
  while (match("}") == 0)
    if(eof) {
      error("no final }");
      break;
      }
    else statement();     /* do one */
  if(--ncmp               /* close current level */
  && lastst != STRETURN
  && lastst != STGOTO)
    gen(ADDSP, savcsp);   /* delete local variable space */
  cptr = savloc;          /* retain labels */
  while(cptr < locptr) {
    cptr2 = nextsym(cptr);
    if(cptr[IDENT] == LABEL) {
      while(cptr < cptr2) *savloc++ = *cptr++;
      }
    else cptr = cptr2;
    }
  locptr = savloc;        /* delete local symbols */
  declared = -1;          /* may not declare variables */
  }

int doif()  {
  int flab1, flab2;
  test(flab1 = getlabel(), YES);  /* get expr, and branch false */
  statement();                    /* if true, do a statement */
  if(amatch("else", 4) == 0) {    /* if...else ? */
    /* simple "if"...print false label */
    gen(LABm, flab1);
    return;                       /* and exit */
    }
  flab2 = getlabel();
  if(lastst != STRETURN && lastst != STGOTO)
    gen(JMPm, flab2);
  gen(LABm, flab1);    /* print false label */
  statement();         /* and do "else" clause */
  gen(LABm, flab2);    /* print true label */
  }

int dowhile()  {
  int wq[4];              /* allocate local queue */
  addwhile(wq);           /* add entry to queue for "break" */
  gen(LABm, wq[WQLOOP]);  /* loop label */
  test(wq[WQEXIT], YES);  /* see if true */
  statement();            /* if so, do a statement */
  gen(JMPm, wq[WQLOOP]);  /* loop to label */
  gen(LABm, wq[WQEXIT]);  /* exit label */
  delwhile();             /* delete queue entry */
  }

int dodo() {
  int wq[4];
  addwhile(wq);
  gen(LABm, wq[WQLOOP]);
  statement();
  need("while");
  test(wq[WQEXIT], YES);
  gen(JMPm, wq[WQLOOP]);
  gen(LABm, wq[WQEXIT]);
  delwhile();
  ns();
  }

int dofor() {
  int wq[4], lab1, lab2;
  addwhile(wq);
  lab1 = getlabel();
  lab2 = getlabel();
  need("(");
  if(match(";") == 0) {
    doexpr(NO);           /* expr 1 */
    ns();
    }
  gen(LABm, lab1);
  if(match(";") == 0) {
    test(wq[WQEXIT], NO); /* expr 2 */
    ns();
    }
  gen(JMPm, lab2);
  gen(LABm, wq[WQLOOP]);
  if(match(")") == 0) {
    doexpr(NO);           /* expr 3 */
    need(")");
    }
  gen(JMPm, lab1);
  gen(LABm, lab2);
  statement();
  gen(JMPm, wq[WQLOOP]);
  gen(LABm, wq[WQEXIT]);
  delwhile();
  }

int doswitch() {
  int wq[4], endlab, swact, swdef, *swnex, *swptr;
  swact = swactive;
  swdef = swdefault;
  swnex = swptr = swnext;
  addwhile(wq);
  *(wqptr + WQLOOP - WQSIZ) = 0;
  need("(");
  doexpr(YES);                /* evaluate switch expression */
  need(")");
  swdefault = 0;
  swactive = 1;
  gen(JMPm, endlab = getlabel());
  statement();                /* cases, etc. */
  gen(JMPm, wq[WQEXIT]);
  gen(LABm, endlab);
  gen(SWITCH, 0);             /* match cases */
  while(swptr < swnext) {
    gen(NEARm, *swptr++);
    gen(WORDn,  *swptr++);    /* case value */
    }
  gen(WORDn, 0);
  if(swdefault) gen(JMPm, swdefault);
  gen(LABm, wq[WQEXIT]);
  delwhile();
  swnext    = swnex;
  swdefault = swdef;
  swactive  = swact;
  }

int docase() {
  if(swactive == 0) error("not in switch");
  if(swnext > swend) {
    error("too many cases");
    return;
    }
  gen(LABm, *swnext++ = getlabel());
  constexpr(swnext++);
  need(":");
  }

int dodefault() {
  if(swactive) {
    if(swdefault) error("multiple defaults");
    }
  else error("not in switch");
  need(":");
  gen(LABm, swdefault = getlabel());
  }

int dogoto() {
  if(nogo > 0) error("not allowed with block-locals");
  else noloc = 1;
  if(symname(ssname)) gen(JMPm, addlabel(NO));
  else error("bad label");
  ns();
  }

int dolabel() {
  char *savelptr;
  blanks();
  savelptr = lptr;
  if(symname(ssname)) {
    if(gch() == ':') {
      gen(LABm, addlabel(YES));
      return 1;
      }
    else bump(savelptr-lptr);
    }
  return 0;
  }

int addlabel(def) int def; {
  if(cptr = findloc(ssname)) {
    if(cptr[IDENT] != LABEL) error("not a label");
    else if(def) {
      if(cptr[TYPE]) error("duplicate label");
      else cptr[TYPE] = YES;
      }
    }
  else cptr = addsym(ssname, LABEL, def, 0, getlabel(), &locptr, LABEL);
  return (getint(cptr+OFFSET, 2));
  }

int doreturn()  {
  int savcsp;
  if(endst() == 0) {
    if(curtype == VOID) error("void return value");
    doexpr(YES);
    }
  savcsp = csp;
  gen(RETURN, 0);
  csp = savcsp;
  }

int dobreak()  {
  int *ptr;
  if((ptr = readwhile(wqptr)) == 0) return;
  gen(ADDSP, ptr[WQSP]);
  gen(JMPm, ptr[WQEXIT]);
  }

int docont()  {
  int *ptr;
  ptr = wqptr;
  while (1) {
    if((ptr = readwhile(ptr)) == 0) return;
    if(ptr[WQLOOP]) break;
    }
  gen(ADDSP, ptr[WQSP]);
  gen(JMPm, ptr[WQLOOP]);
  }

int doasm()  {
  ccode = 0;           /* mark mode as "asm" */
  while (1) {
    inline();
    if(match("#endasm")) break;
    if(eof)break;
    fputs(line, output);
    }
  kill();
  ccode = 1;
  }

int doexpr(use) int use; {
  int cnst, val;
  int *before, *start;
  usexpr = use;        /* tell isfree() whether expr value is used */
  while(1) {
    setstage(&before, &start);
    expression(&cnst, &val);
    clearstage(before, start);
    if(ch != ',') break;
    bump(1);
    }
  usexpr = YES;        /* return to normal value */
  }

/******************** miscellaneous functions *******************/

/*
** get run options
*/
int ask() {
  int i;
  i = listfp = nxtlab = 0;
  output = stdout;
  objectmode = NO;
  optimize = YES;
#ifdef TARGET_MICROCPU
  optimize = NO;
#endif
  alarm = monitor = pause = NO;
  line = mline;
  while(getarg(++i, line, LINESIZE, argcs, argvs) != EOF) {
    if(line[0] != '-' && line[0] != '/') continue;
    if(toupper(line[1]) == 'D') {
      if(line[2] > ' ') defarg(line+2);
      else {
        if(getarg(++i, line, LINESIZE, argcs, argvs) == EOF) {
          fputs("missing macro name after -D\n", stderr);
          abort(ERRCODE);
          }
        defarg(line);
        addskiparg(i);
        }
      continue;
      }
    if(toupper(line[1]) == 'I') {
      if(line[2] > ' ') addincpath(line+2);
      else {
        if(getarg(++i, line, LINESIZE, argcs, argvs) == EOF) {
          fputs("missing include directory after -I\n", stderr);
          abort(ERRCODE);
          }
        addincpath(line);
        addskiparg(i);
        }
      continue;
      }
    if(toupper(line[1]) == 'L'
    && isdigit(line[2])
    && line[3] <= ' ') {
      listfp = line[2]-'0';
      continue;
      }
    if(toupper(line[1]) == 'N'
    && toupper(line[2]) == 'O'
    && line[3] <= ' ') {
      optimize = NO;
      continue;
      }
    if(line[1] == '-'
    && line[2] == 'o'
    && line[3] == 'b'
    && line[4] == 'j'
    && line[5] == 'e'
    && line[6] == 'c'
    && line[7] == 't'
    && line[8] <= ' ') {
      objectmode = YES;
      continue;
      }
    if(line[2] <= ' ') {
      if(toupper(line[1]) == 'A') {alarm   = YES; continue;}
      if(toupper(line[1]) == 'M') {monitor = YES; continue;}
      if(toupper(line[1]) == 'P') {pause   = YES; continue;}
      }
    fputs("usage: cc [file]... [-Dname[=value]] [-Idir] [--object] [-m] [-a] [-p] [-l#] [-no]\n", stderr);
    abort(ERRCODE);
    }
  }

int addincpath(path) char *path; {
  char *dst;
  int i;
  if(incpath_count >= MAXINCPATHS) {
    error("include path table overflow");
    return 0;
    }
  dst = incpath + incpath_count * LINESIZE;
  i = 0;
  while(path[i] && i < LINEMAX) {
    dst[i] = path[i];
    ++i;
    }
  dst[i] = 0;
  ++incpath_count;
  return 1;
  }

int addskiparg(index) int index; {
  if(skip_count < MAXSKIPARGS) skip_arg[skip_count++] = index;
  }

int skipfilearg(index) int index; {
  int i;
  i = 0;
  while(i < skip_count) {
    if(skip_arg[i] == index) return 1;
    ++i;
    }
  return 0;
  }

/*
** input and output file opens
*/
int openfile() {        /* entire function revised */
  char outfn[15];
  int i, j, ext;
  input = EOF;
  while(getarg(++filearg, pline, LINESIZE, argcs, argvs) != EOF) {
    if(skipfilearg(filearg)) continue;
    if(pline[0] == '-' || pline[0] == '/') continue;
    ext = NO;
    i = -1;
    j = 0;
    while(pline[++i]) {
      if(pline[i] == '.') {
        ext = YES;
        break;
        }
      if(j < 10) outfn[j++] = pline[i];
      }
    if(!ext) strcpy(pline + i, ".C");
    input = mustopen(pline, "r");
    setcurdir(pline, incdir);
    if(!files && iscons(stdout)) {
      strcpy(outfn + j, ".ASM");
      output = mustopen(outfn, "w");
      }
    files = YES;
    kill();
    return;
    }
  if(files++) eof = YES;
  else input = stdin;
  *incdir = 0;
  kill();
  }

int setcurdir(path, dst) char *path, *dst; {
  int i, slash, j;
  i = slash = 0;
  while(path[i]) {
    if(path[i] == '/' || path[i] == '\\') slash = i + 1;
    ++i;
    }
  j = 0;
  while(j < slash && j < LINEMAX) {
    dst[j] = path[j];
    ++j;
    }
  dst[j] = 0;
  }

int pathjoin(dir, name, dst) char *dir, *name, *dst; {
  int i, j;
  i = 0;
  while(dir[i] && i < LINEMAX) {
    dst[i] = dir[i];
    ++i;
    }
  if(i && dst[i-1] != '/' && dst[i-1] != '\\' && i < LINEMAX)
    dst[i++] = '/';
  j = 0;
  while(name[j] && i < LINEMAX) dst[i++] = name[j++];
  dst[i] = 0;
  }

int tryinclude(dir, name, outpath) char *dir, *name, *outpath; {
  int fd;
  if(dir && *dir) pathjoin(dir, name, outpath);
  else strcpy(outpath, name);
  if(fd = fopen(outpath, "r")) return fd;
  return 0;
  }

int openinclude(name, quoted) char *name; int quoted; {
  int fd, i;
  char path[LINESIZE];
  if(inclevel >= MAXINCLUDE) {
    error("include nesting too deep");
    return 0;
    }
  fd = 0;
  if(quoted) fd = tryinclude(incdir + inclevel * LINESIZE, name, path);
  i = 0;
  while(fd == 0 && i < incpath_count) {
    fd = tryinclude(incpath + i * LINESIZE, name, path);
    ++i;
    }
  if(fd == 0) fd = tryinclude("include", name, path);
  if(fd == 0) fd = tryinclude("smallc-microcpu/include", name, path);
  if(fd == 0) {
    error("open failure on include file");
    return 0;
    }
  incfile[inclevel++] = fd;
  ++include_open_count;
  setcurdir(path, incdir + inclevel * LINESIZE);
  input2 = fd;
  return 1;
  }

/*
** open a file with error checking
*/
int mustopen(fn, mode) char *fn, *mode; {
  int fd;
  if(fd = fopen(fn, mode)) return fd;
  fputs("open error on ", stderr);
  lout(fn, stderr);
  abort(ERRCODE);
  }


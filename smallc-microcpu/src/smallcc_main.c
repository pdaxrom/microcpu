/*
** Small-C microcpu compiler-only main module.
** Copyright 1982, 1983, 1985, 1988 J. E. Hendrix
** All rights reserved.
*/
#define SMALLCC_DRIVER
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
  backend, /* selected output backend */
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
  field_offset[MAXFIELDS]
#ifndef SMALLCC_DRIVER
  ,
  incfile[MAXINCLUDE],
  skip_arg[MAXSKIPARGS],
  macro_argc[MACNBR],
  macro_argfirst[MACNBR]
#endif
  ;

char
  dummy_smallc_char;
#ifndef SMALLCC_DRIVER
char
  incpath[MAXINCPATHS * LINESIZE],
  incdir[(MAXINCLUDE + 1) * LINESIZE],
  macro_param_name[MAXMACPARAMS * MACNAMESIZE];
#endif

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
#ifndef SMALLCC_DRIVER
  macn    = calloc(MACNSIZE, 1);
  macq    = calloc(MACQSIZE, 1);
#endif
  pline   = calloc(LINESIZE, 1);
#ifndef SMALLCC_DRIVER
  mline   = calloc(LINESIZE, 1);
#endif
  slast   = stage+(STAGESIZE*2*BPW);
  symtab  = calloc((NUMLOCS*SYMAVG + NUMGLBS*SYMMAX), 1);
  locptr  = STARTLOC;
  glbptr  = STARTGLB;

#ifdef SMALLCC_DRIVER
  smallcc_ask();  /* get user options and initial .i input */
#else
  ask();          /* get user options */
  openfile();     /* and initial input file */
#endif
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
#ifndef SMALLCC_DRIVER
    else if( match("#include"))  doinclude();
    else if( match("#define"))   dodefine();
    else if( match("#undef"))    doundef();
#else
    else if( match("#"))         error("preprocessor directive in .i input");
#endif
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

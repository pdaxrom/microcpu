/*
** Small-C microcpu standalone preprocessor.
** Based on Small-C 2.2 Revision Level 117 by J. E. Hendrix.
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

int smallcpp_main(argc, argv)
  int argc, *argv; {
  fputs(VERSION, stderr);
  fputs(CRIGHT1, stderr);
  argcs = argc;
  argvs = argv;
  macn = calloc(MACNSIZE, 1);
  macq = calloc(MACQSIZE, 1);
  pline = calloc(LINESIZE, 1);
  mline = calloc(LINESIZE, 1);
  line = mline;
  symtab = calloc((NUMLOCS*SYMAVG + NUMGLBS*SYMMAX), 1);
  locptr = STARTLOC;
  glbptr = STARTGLB;
  ask();
  openfile();
  while(eof == 0) {
    preprocess();
    if(eof) break;
    if(match("#include")) doinclude();
    else if(match("#define")) dodefine();
    else if(match("#undef")) doundef();
    else {
      fputs(line, output);
      fputc(NEWLINE, output);
      }
    }
  fclose(output);
  return 0;
  }

#ifndef SMALLC_SELFHOST
#undef int
int main(int host_argc, char **host_argv)
{
  return (int)smallcpp_main((intptr_t)host_argc, (intptr_t *)host_argv);
}
#define int intptr_t
#else
int main(argc, argv)
  int argc, *argv; {
  return smallcpp_main(argc, argv);
  }
#endif

/*
** Small-C Compiler -- Part 2 -- Front End and Miscellaneous.
** Copyright 1982, 1983, 1985, 1988 J. E. Hendrix
** All rights reserved.
*/

#include <stdio.h>
#include "cc.h"
#include "host_compat.h"

extern char
 *symtab, *macn, *macq, *pline, *mline,  optimize,
  alarm, *glbptr, *line, *lptr, *cptr, *cptr2,  *cptr3,
 *locptr, msname[MACNAMESIZE],  pause,  quote[2],
  macro_param_name[MAXMACPARAMS * MACNAMESIZE];

extern int
  *wq,  ccode,  ch,  csp,  eof,  errflag,  iflevel,
  input,  input2,  inclevel,  incfile[MAXINCLUDE],  listfp,  macptr,  nch,
  nxtlab,  op[16],  opindex,  opsize,  output,  pptr,
  skiplevel,  *wqptr,  macro_argc[MACNBR],  macro_argfirst[MACNBR];

/********************** input functions **********************/

int preprocess() {
  int k;
  char c;
  if(ccode) {
    line = mline;
    ifline();
    if(eof) return;
    }
  else {
    inline();
    return;
    }
  pptr = -1;
  if(streq(lptr, "#define")
  || streq(lptr, "#undef")
  || streq(lptr, "#include")) {
    while(ch != NEWLINE && ch) keepch(gch());
    keepch(NULL);
    line = pline;
    bump(0);
    return;
    }
  while(ch != NEWLINE && ch) {
    if(white()) {
      keepch(' ');
      while(white()) gch();
      }
    else if(ch == '"') {
      keepch(ch);
      gch();
      while(ch != '"' || (*(lptr-1) == 92 && *(lptr-2) != 92)) {
        if(ch == NULL) {
          error("no quote");
          break;
          }
        keepch(gch());
        }
      gch();
      keepch('"');
      }
    else if(ch == 39) {
      keepch(39);
      gch();
      while(ch != 39 || (*(lptr-1) == 92 && *(lptr-2) != 92)) {
        if(ch == NULL) {
          error("no apostrophe");
          break;
          }
        keepch(gch());
        }
      gch();
      keepch(39);
      }
    else if(ch == '/' && nch == '*') {
      bump(2);
      while((ch == '*' && nch == '/') == 0) {
        if(ch) bump(1);
        else {
          ifline();
          if(eof) break;
          }
        }
      bump(2);
      }
    else if(an(ch)) {
      k = 0;
      while(an(ch)) {
        c = gch();
        if(k < MACNAMEMAX) msname[k++] = c;
        }
      msname[k] = NULL;
      if(macsearch(msname)) {
        cptr2 = expandfound(cptr, lptr, 0);
        if(cptr2 != lptr) bump(cptr2 - lptr);
        }
      else {
        k = 0;
        while(c = msname[k++]) keepch(c);
        }
      }
    else keepch(gch());
    }
  if(pptr >= LINEMAX) error("line too long");
  keepch(NULL);
  line = pline;
  bump(0);
  }

int keepch(c)  char c; {
  if(pptr < LINEMAX) pline[++pptr] = c;
  }

int ifline() {
  while(1) {
    inline();
    if(eof) return;
    if(match("#ifdef")) {
      ++iflevel;
      if(skiplevel) continue;
      macsymname(msname);
      if(macsearch(msname) == 0)
        skiplevel = iflevel;
      continue;
      }
    if(match("#ifndef")) {
      ++iflevel;
      if(skiplevel) continue;
      macsymname(msname);
      if(macsearch(msname))
        skiplevel = iflevel;
      continue;
      }
    if(match("#else")) {
      if(iflevel) {
        if(skiplevel == iflevel) skiplevel = 0;
        else if(skiplevel == 0)  skiplevel = iflevel;
        }
      else noiferr();
      continue;
      }
    if(match("#endif")) {
      if(iflevel) {
        if(skiplevel == iflevel) skiplevel = 0;
        --iflevel;
        }
      else noiferr();
      continue;
      }
    if(match("#if")) {
      error("unsupported #if");
      continue;
      }
    if(skiplevel) continue;
    if(ch == 0) continue;
    break;
    }
  }

int inline() {           /* numerous revisions */
  int k, unit;
  poll(1);           /* allow operator interruption */
  if(input == EOF) openfile();
  if(eof) return;
  if(inclevel) unit = incfile[inclevel-1];
  else         unit = input;
  if(fgets(line, LINEMAX, unit) == NULL) {
    fclose(unit);
    if(inclevel) {
      --inclevel;
      if(inclevel) input2 = incfile[inclevel-1];
      else         input2 = EOF;
      }
    else input  = EOF;
    *line = NULL;
    }
  else if(listfp) {
    if(listfp == output) fputc(';', output);
    fputs(line, listfp);
    }
  bump(0);
  }

int inbyte()  {
  while(ch == 0) {
    if(eof) return 0;
    preprocess();
    }
  return gch();
  }

/********************* scanning functions ********************/

/*
** test if next input string is legal macro name
*/
int macsymname(sname) char *sname; {
  int k;char c;
  blanks();
  if(alpha(ch) == 0) return (*sname = 0);
  k = 0;
  while(an(ch)) {
    c = gch();
    if(k < MACNAMEMAX) sname[k++] = c;
    }
  sname[k] = 0;
  return 1;
  }

/*
** search for macro match
*/
int macsearch(sname) char *sname; {
  cptr  =
  cptr2 = macn+((hash(sname)%(MACNBR-1))*MACENTRY);
  while(*cptr != NULL) {
    if(astreq(sname, cptr, MACNAMEMAX)) return 1;
    if((cptr = cptr+MACENTRY) >= MACNEND) cptr = macn;
    if(cptr == cptr2) return (cptr = 0);
    }
  return 0;
  }

int expandfound(ptr, src, depth) char *ptr, *src; int depth; {
  int idx, off, argc;
  char args[MAXMACARGS * LINESIZE], subst[LINESIZE];
  char *p, *q;
  if(depth >= MAXMACEXPAND) {
    error("macro expansion depth exceeded");
    return src;
    }
  idx = macindex(ptr);
  argc = macro_argc[idx];
  off = getint(ptr+MACNAMESIZE, 2);
  if(argc < 0) {
    expandtext(macq + off, depth + 1);
    return src;
    }
  p = src;
  while(*p && *p <= ' ') ++p;
  if(*p != '(') {
    expandname(ptr);
    return src;
    }
  q = readmacroargs(p + 1, argc, args);
  if(q == 0) {
    expandname(ptr);
    return src;
    }
  substmacro(idx, args, subst);
  expandtext(subst, depth + 1);
  return q;
  }

int expandtext(text, depth) char *text; int depth; {
  int k;
  char c, name[MACNAMESIZE], *p;
  p = text;
  while(c = *p) {
    if(c == '"') {
      keepch(*p++);
      while(*p && (*p != '"' || (*(p-1) == 92 && *(p-2) != 92)))
        keepch(*p++);
      if(*p) keepch(*p++);
      }
    else if(c == 39) {
      keepch(*p++);
      while(*p && (*p != 39 || (*(p-1) == 92 && *(p-2) != 92)))
        keepch(*p++);
      if(*p) keepch(*p++);
      }
    else if(alpha(c)) {
      k = 0;
      while(an(*p)) {
        c = *p++;
        if(k < MACNAMEMAX) name[k++] = c;
        }
      name[k] = 0;
      if(macsearch(name))
        p = expandfound(cptr, p, depth);
      else {
        k = 0;
        while(c = name[k++]) keepch(c);
        }
      }
    else keepch(*p++);
    }
  }

int expandname(ptr) char *ptr; {
  int k;
  k = 0;
  while(ptr[k]) keepch(ptr[k++]);
  }

int readmacroargs(src, argc, args) char *src, *args; int argc; {
  int arg, depth, len, c;
  char *p, *dst;
  p = src;
  arg = depth = len = 0;
  dst = args;
  if(argc == 0) {
    while(*p && *p <= ' ') ++p;
    if(*p == ')') return p + 1;
    error("wrong macro argument count");
    return 0;
    }
  while(*p) {
    c = *p++;
    if(c == '"' || c == 39) {
      if(len < LINEMAX) {dst[len++] = c;}
      while(*p && (*p != c || (*(p-1) == 92 && *(p-2) != 92))) {
        if(len < LINEMAX) dst[len++] = *p;
        ++p;
        }
      if(*p && len < LINEMAX) dst[len++] = *p++;
      }
    else if(c == '(') {
      ++depth;
      if(len < LINEMAX) dst[len++] = c;
      }
    else if(c == ')' && depth) {
      --depth;
      if(len < LINEMAX) dst[len++] = c;
      }
    else if((c == ',' || c == ')') && depth == 0) {
      dst[len] = 0;
      ++arg;
      if(c == ')') {
        if(arg != argc) error("wrong macro argument count");
        return p;
        }
      if(arg >= argc || arg >= MAXMACARGS) {
        error("wrong macro argument count");
        return 0;
        }
      dst = args + arg * LINESIZE;
      len = 0;
      }
    else {
      if(len < LINEMAX) dst[len++] = c;
      }
    }
  error("missing macro close paren");
  return 0;
  }

int substmacro(idx, args, out) int idx; char *args, *out; {
  int k, pi;
  char c, name[MACNAMESIZE], *p;
  p = macq + getint(macn + idx * MACENTRY + MACNAMESIZE, 2);
  *out = 0;
  while(c = *p) {
    if(c == '"' || c == 39) {
      appendchar(out, c);
      ++p;
      while(*p && (*p != c || (*(p-1) == 92 && *(p-2) != 92))) {
        appendchar(out, *p);
        ++p;
        }
      if(*p) appendchar(out, *p++);
      }
    else if(alpha(c)) {
      k = 0;
      while(an(*p)) {
        c = *p++;
        if(k < MACNAMEMAX) name[k++] = c;
        }
      name[k] = 0;
      pi = findmacroparam(idx, name);
      if(pi >= 0) appendtext(out, args + pi * LINESIZE);
      else        appendtext(out, name);
      }
    else {
      appendchar(out, *p);
      ++p;
      }
    }
  }

int appendtext(out, text) char *out, *text; {
  while(*text) appendchar(out, *text++);
  }

int appendchar(out, c) char *out; int c; {
  int i;
  i = 0;
  while(out[i]) ++i;
  if(i < LINEMAX) {
    out[i++] = c;
    out[i] = 0;
    }
  }

int findmacroparam(idx, name) int idx; char *name; {
  int i, count, first;
  char *p;
  count = macro_argc[idx];
  first = macro_argfirst[idx];
  i = 0;
  while(i < count) {
    p = macro_param_name + (first + i) * MACNAMESIZE;
    if(astreq(name, p, MACNAMEMAX)) return i;
    ++i;
    }
  return -1;
  }

/*
** test if next input string is legal symbol name
*/
int symname(sname) char *sname; {
  int k;char c;
  blanks();
  if(alpha(ch) == 0) return (*sname = 0);
  k = 0;
  while(an(ch)) {
    sname[k] = gch();
    if(k < NAMEMAX) ++k;
    }
  sname[k] = 0;
  return 1;
  }

int need(str)  char *str; {
  if(match(str) == 0) error("missing token");
  }

int ns()  {
  if(match(";") == 0) error("no semicolon");
  else errflag = 0;
  }

int match(lit)  char *lit; {
  int k;
  blanks();
  if(k = streq(lptr, lit)) {
    bump(k);
    return 1;
    }
  return 0;
  }

int streq(str1, str2)  char str1[], str2[]; {
  int k;
  k = 0;
  while (str2[k]) {
    if(str1[k] != str2[k]) return 0;
    ++k;
    }
  return k;
 }

int amatch(lit, len)  char *lit; int len; {
  int k;
  blanks();
  if(k = astreq(lptr, lit, len)) {
    bump(k);
    return 1;
    }
  return 0;
 }

int astreq(str1, str2, len)  char str1[], str2[]; int len; {
  int k;
  k = 0;
  while (k < len) {
    if(str1[k] != str2[k]) break;
    /*
    ** must detect end of symbol table names terminated by
    ** symbol length in binary
    */
    if(str2[k] < ' ') break;
    if(str1[k] < ' ') break;
    ++k;
    }
  if(an(str1[k]) || an(str2[k])) return 0;
  return k;
  }

int nextop(list) char *list; {
  char op[4];
  opindex = 0;
  blanks();
  while(1) {
    opsize = 0;
    while(*list > ' ') op[opsize++] = *list++;
    op[opsize] = 0;
    if(opsize = streq(lptr, op))
      if(*(lptr+opsize) != '=' && 
         *(lptr+opsize) != *(lptr+opsize-1))
         return 1;
    if(*list) {
      ++list;
      ++opindex;
      }
    else return 0;
    }
  }

int blanks() {
  while(1) {
    while(ch) {
      if(white()) gch();
      else return;
      }
    if(line == mline) return;
    preprocess();
    if(eof) break;
    }
  }

int white() {
  avail(YES);  /* abort on stack/symbol table overflow */
  return (*lptr <= ' ' && *lptr);
  }

int gch() {
  int c;
  if(c = ch) bump(1);
  return c;
  }

int bump(n) int n; {
  if(n) lptr += n;
  else  lptr  = line;
  if(ch = nch = *lptr) nch = *(lptr+1);
  }

int kill() {
  *line = 0;
  bump(0);
  }

int skip() {
  if(an(inbyte()))
       while(an(ch)) gch();
  else while(an(ch) == 0) {
    if(ch == 0) break;
    gch();
    }
  blanks();
  }

int endst() {
  blanks();
  return (streq(lptr, ";") || ch == 0);
  }

/*********** symbol table management functions ***********/

int addsym(sname, id, type, size, value, lgpp, class)
  char *sname, id, type, **lgpp;  int size, value, class; {
  if(lgpp == &glbptr) {
    if(cptr2 = findglb(sname)) return cptr2;
    if(cptr == 0) {
      error("global symbol table overflow");
      return 0;
      }
    }
  else {
    if(locptr > (ENDLOC-SYMMAX)) {
      error("local symbol table overflow");
      abort(ERRCODE);
      }
    cptr = *lgpp;
    }
  cptr[IDENT] = id;
  cptr[TYPE]  = type;
  cptr[CLASS] = class;
  putint(size, cptr + SIZE, 2);
  putint(value, cptr + OFFSET, 2);
  cptr3 = cptr2 = cptr + NAME;
  while(an(*sname)) *cptr2++ = *sname++;
  if(lgpp == &locptr) {
    *cptr2 = cptr2 - cptr3;         /* set length */
    *lgpp = ++cptr2;
    }
  return cptr;
  }

/*
** search for symbol match
** on return cptr points to slot found or empty slot
*/
int search(sname, buf, len, end, max, off)
  char *sname, *buf, *end;  int len, max, off; {
  cptr  =
  cptr2 = buf+((hash(sname)%(max-1))*len);
  while(*cptr != NULL) {
    if(astreq(sname, cptr+off, NAMEMAX)) return 1;
    if((cptr = cptr+len) >= end) cptr = buf;
    if(cptr == cptr2) return (cptr = 0);
    }
  return 0;
  }

int hash(sname) char *sname; {
  int i, c;
  i = 0;
  while(c = *sname++) i = (i << 1) + c;
  return i;
  }

int findglb(sname)  char *sname; {
  if(search(sname, STARTGLB, SYMMAX, ENDGLB, NUMGLBS, NAME))
    return cptr;
  return 0;
  }

int findloc(sname)  char *sname;  {
  cptr = locptr - 1;  /* search backward for block locals */
  while(cptr > STARTLOC) {
    cptr = cptr - *cptr;
    if(astreq(sname, cptr, NAMEMAX)) return (cptr - NAME);
    cptr = cptr - NAME - 1;
    }
  return 0;
  }

int nextsym(entry) char *entry; {
  entry = entry + NAME;
  while(*entry++ >= ' ');    /* find length byte */
  return entry;
  }

/******** while queue management functions *********/  

int addwhile(ptr)  int ptr[]; {
  int k;
  ptr[WQSP]   = csp;         /* and stk ptr */
  ptr[WQLOOP] = getlabel();  /* and looping label */
  ptr[WQEXIT] = getlabel();  /* and exit label */
  if(wqptr == WQMAX) {
    error("control statement nesting limit");
    abort(ERRCODE);
    }
  k = 0;
  while (k < WQSIZ) *wqptr++ = ptr[k++];
  }

int readwhile(ptr) int *ptr; {
  if(ptr <= wq) {
    error("out of context");
    return 0;
    }
  else return (ptr - WQSIZ);
 }

int delwhile() {
  if(wqptr > wq) wqptr -= WQSIZ;
  }

/****************** utility functions ********************/  

/*
** test if c is alphabetic
*/
int alpha(c)  char c; {
  return (isalpha(c) || c == '_');
  }

/*
** test if given character is alphanumeric
*/
int an(c)  char c; {
  return (alpha(c) || isdigit(c));
  }

/*
** return next avail internal label number
*/
int getlabel() {
  return(++nxtlab);
  }

/*
** get integer of length len from address addr
** (byte sequence set by "putint")
*/
int getint(addr, len) char *addr; int len; {
  int i;
  i = *(addr + --len);  /* high order byte sign extended */
  while(len--) i = (i << 8) | *(addr + len) & 255;
  return i;
  }

/*
** put integer i of length len into address addr
** (low byte first)
*/
int putint(i, addr, len) char *addr; int i, len; {
  while(len--) {
    *addr++ = i;
    i = i >> 8;
    }
  }

int lout(line, fd) char *line; int fd; {
  fputs(line, fd);
  fputc(NEWLINE, fd);
  }

/******************* error functions *********************/  

int illname() {
  error("illegal symbol");
  skip();
  }

int multidef(sname)  char *sname; {
  error("already defined");
  }

int needlval() {
  error("must be lvalue");
  }

int noiferr() {
  error("no matching #if...");
  errflag = 0;
  }

int error(msg) char msg[]; {
  if(errflag) return;
  else errflag = 1;
  lout(line, stderr);
  errout(msg, stderr);
  if(alarm) fputc(7, stderr);
  if(pause) while(fgetc(stderr) != NEWLINE);
  if(listfp > 0) errout(msg, listfp);
  }

int errout(msg, fp) char msg[]; int fp; {
  char *k;
  k = line+2;
  while(k++ <= lptr) fputc(' ', fp);
  lout("/\\", fp);
  fputs("**** ", fp); lout(msg, fp);
  }


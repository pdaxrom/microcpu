/*
** Small-C microcpu canonical split module.
** Copyright 1982, 1983, 1985, 1988 J. E. Hendrix
** All rights reserved.
*/
#include <stdio.h>
#include "cc.h"
#include "host_compat.h"
#include "smallcc_globals.h"

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
  argtop = argstk+BPW;         /* account for saved frame word */
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

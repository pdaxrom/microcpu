/*
** Small-C microcpu canonical split module.
** Copyright 1982, 1983, 1985, 1988 J. E. Hendrix
** All rights reserved.
*/
#include <stdio.h>
#include "cc.h"
#include "host_compat.h"
#include "smallcc_globals.h"

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

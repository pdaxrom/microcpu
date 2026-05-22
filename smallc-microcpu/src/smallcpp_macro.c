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

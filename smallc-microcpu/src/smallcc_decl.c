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
** declare a static variable
*/
int declglb(type, class)  int type, class; {
  declglb2(type, class, VARIABLE);
  }

int declglb2(type, class, baseid)  int type, class, baseid; {
  int id, dim, stars, levels, dtype, size, p;
  char *ptr;
  while(1) {
    contline();
    if(endst()) return;  /* do line */
    stars = 0;
    p = 0;
    skipconst();
    while(match("*")) {
      ++stars;
      skipconst();
      }
    if(match("(")) {
      p = 1;
      skipconst();
      while(match("*")) {
        ++stars;
        skipconst();
        }
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
    if(p) {
      need(")");
      if(match("(")) skipprotoargs();
      }
    else if(match("(")) {
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

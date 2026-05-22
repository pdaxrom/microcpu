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

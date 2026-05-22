/*
** Small-C microcpu canonical split module.
** Copyright 1982, 1983, 1985, 1988 J. E. Hendrix
** All rights reserved.
*/
#include <stdio.h>
#include "cc.h"
#include "host_compat.h"
#include "smallcc_globals.h"

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
  optimize = NO;
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
    if(line[1] == 'o' && line[2] <= ' ') {
      if(getarg(++i, line, LINESIZE, argcs, argvs) == EOF) {
        fputs("missing output file after -o\n", stderr);
        abort(ERRCODE);
        }
      output = mustopen(line, "w");
      addskiparg(i);
      continue;
      }
    if(line[1] == 'o' && line[2] > ' ') {
      output = mustopen(line+2, "w");
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

/*
** Small-C microcpu compiler-only driver for preprocessed input.
*/
#include <stdio.h>
#include "cc.h"
#include "host_compat.h"

extern int
  argcs, *argvs, input, output, objectmode, listfp, nxtlab;

extern char
  *line, *pline;

int smallcc_open(name) char *name; {
  int fd;
  if(fd = fopen(name, "r")) return fd;
  fputs("open error on ", stderr);
  lout(name, stderr);
  abort(ERRCODE);
  }

int smallcc_out(name) char *name; {
  int fd;
  if(fd = fopen(name, "w")) return fd;
  fputs("open error on ", stderr);
  lout(name, stderr);
  abort(ERRCODE);
  }

int smallcc_ask() {
  int i;
  int skipnext;
  i = 0;
  skipnext = NO;
  listfp = nxtlab = 0;
  output = stdout;
  input = EOF;
  objectmode = NO;
  line = pline;
  while(getarg(++i, line, LINESIZE, argcs, argvs) != EOF) {
    if(skipnext) {
      skipnext = NO;
      continue;
      }
    if(line[0] == '-' || line[0] == '/') {
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
      if(line[1] == 'o' && line[2] <= ' ') {
        if(getarg(++i, line, LINESIZE, argcs, argvs) == EOF) {
          fputs("missing output file after -o\n", stderr);
          abort(ERRCODE);
          }
        output = smallcc_out(line);
        continue;
        }
      if(line[1] == 'o' && line[2] > ' ') {
        output = smallcc_out(line+2);
        continue;
        }
      if((toupper(line[1]) == 'I' || toupper(line[1]) == 'D')
      && line[2] <= ' ') {
        skipnext = YES;
        continue;
        }
      if(toupper(line[1]) == 'I' || toupper(line[1]) == 'D') continue;
      fputs("usage: smallcc [--object] [-o file] file.i\n", stderr);
      abort(ERRCODE);
      }
    if(input == EOF) input = smallcc_open(line);
    }
  if(input == EOF) input = stdin;
  }

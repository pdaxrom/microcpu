/*
** Small-C Compiler -- preprocessed input reader.
** Copyright 1982, 1983, 1985, 1988 J. E. Hendrix
** All rights reserved.
*/
#include <stdio.h>
#include "cc.h"
#include "host_compat.h"

extern char
 *pline, *line, *lptr;

extern int
  input, eof, pptr, ch, nch, output, listfp;

int preprocess() {
  line = pline;
  inline();
  if(eof) return;
  pptr = -1;
  while(ch != NEWLINE && ch) keepch(gch());
  keepch(NULL);
  line = pline;
  bump(0);
  }

int keepch(c) char c; {
  if(pptr < LINEMAX) pline[++pptr] = c;
  }

int inline() {
  poll(1);
  if(eof) return;
  if(input == EOF) {
    eof = YES;
    *line = NULL;
    bump(0);
    return;
    }
  if(fgets(line, LINEMAX, input) == NULL) {
    fclose(input);
    input = EOF;
    eof = YES;
    *line = NULL;
    }
  else if(listfp) {
    if(listfp == output) fputc(';', output);
    fputs(line, listfp);
    }
  bump(0);
  }

int inbyte() {
  while(ch == 0) {
    if(eof) return 0;
    preprocess();
    }
  return gch();
  }

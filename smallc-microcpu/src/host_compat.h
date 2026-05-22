/*
** Host portability layer for building Hendrix Small-C with a modern C compiler.
**
** The original compiler was written for a 16-bit hosted C environment where
** int could also hold pointers and FILE handles.  The adapted compiler keeps
** that source model by remapping int to a pointer-sized host word after the
** system headers have been included.
*/
#ifndef HOST_COMPAT_H
#define HOST_COMPAT_H

#include <ctype.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef intptr_t sc_word;

#ifndef YES
#define YES 1
#endif
#ifndef NO
#define NO 0
#endif
#ifndef LF
#define LF 10
#endif
#ifndef NEWLINE
#define NEWLINE LF
#endif

#ifdef SMALLC_SELFHOST
int getarg();
int iscons();
int poll();
int avail();
sc_word sc_fopen();
int sc_fclose();
char *sc_fgets();
int sc_fputs();
int sc_fputc();
#else
int getarg(sc_word order, char *dst, sc_word dst_size, sc_word argc,
    sc_word *argv);
int iscons(void *stream);
void poll(sc_word allow);
void avail(sc_word abort_on_error);
sc_word sc_fopen(const char *path, const char *mode);
int sc_fclose(sc_word stream);
char *sc_fgets(char *buf, sc_word size, sc_word stream);
int sc_fputs(const char *text, sc_word stream);
int sc_fputc(sc_word ch, sc_word stream);
#endif

#define abort(code) exit((int)(code))

#ifndef SMALLC_SELFHOST
#ifndef SMALLC_NO_INT_REMAP
#define inline sc_inline
#define const sc_const
#define double sc_double
#define int intptr_t
#define fopen(path, mode) sc_fopen((path), (mode))
#define fclose(stream) sc_fclose((sc_word)(stream))
#define fgets(buf, size, stream) sc_fgets((buf), (sc_word)(size), (sc_word)(stream))
#define fputs(text, stream) sc_fputs((text), (sc_word)(stream))
#define fputc(ch, stream) sc_fputc((sc_word)(ch), (sc_word)(stream))
#include "smallc_proto.h"
#endif
#endif

#endif

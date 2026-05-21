/*
** Host portability routines for the microcpu Small-C port.
*/
#define SMALLC_NO_INT_REMAP
#include <stdio.h>
#include "host_compat.h"

int getarg(sc_word order, char *dst, sc_word dst_size, sc_word argc,
    sc_word *argv)
{
    const char *src;
    size_t limit;

    if (order < 0 || order >= argc) {
        return EOF;
    }
    src = (const char *)(uintptr_t)argv[order];
    if (src == NULL || dst == NULL || dst_size <= 0) {
        return EOF;
    }
    limit = (size_t)dst_size - 1u;
    strncpy(dst, src, limit);
    dst[limit] = '\0';
    return 0;
}

int iscons(void *stream)
{
    (void)stream;
    return 0;
}

void poll(sc_word allow)
{
    (void)allow;
}

void avail(sc_word abort_on_error)
{
    (void)abort_on_error;
}

sc_word sc_fopen(const char *path, const char *mode)
{
    return (sc_word)(uintptr_t)fopen(path, mode);
}

int sc_fclose(sc_word stream)
{
    return fclose((FILE *)(uintptr_t)stream);
}

char *sc_fgets(char *buf, sc_word size, sc_word stream)
{
    return fgets(buf, (int)size, (FILE *)(uintptr_t)stream);
}

int sc_fputs(const char *text, sc_word stream)
{
    return fputs(text, (FILE *)(uintptr_t)stream);
}

int sc_fputc(sc_word ch, sc_word stream)
{
    return fputc((int)ch, (FILE *)(uintptr_t)stream);
}

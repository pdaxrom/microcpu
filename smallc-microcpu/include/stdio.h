#ifndef SMALLC_STDIO_H
#define SMALLC_STDIO_H

#define EOF -1
#define NULL 0

typedef int FILE;

extern int stdin;
extern int stdout;
extern int stderr;

int printf();
int fprintf();
int sprintf();
int fopen();
int fclose();
int fgetc();
int fgets();
int fputc();
int fputs();
int fread();
int fwrite();
int fflush();

#endif

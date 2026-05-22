# Small-C for microcpu

This is an initial microcpu backend for James E. Hendrix Small-C 2.2,
Revision Level 117.  The untouched baseline imported from the DosWorld
repository is kept under `original/C/`; the buildable port is under `src/`.
Original copyright notices are preserved in the copied source files.

## Build

```sh
make -C smallc-microcpu
```

Compile and verify the tests:

```sh
make -C smallc-microcpu test
```

The test target compiles every `tests/*.c` file to readable microasm, assembles
it with `../asm/microasm`, runs it on `../microemu/microemu`, and checks `V0`
(`r3` in the emulator register dump) against `tests/expected.txt`.
Tests listed in `tests/expected_uart.txt` also compare UART TX output, and
tests listed in `tests/input_uart.txt` preload UART RX using `microemu
--uart-rx`.

The emulator defaults are:

```sh
EMU=../microemu/microemu
EMU_BOARD=hc1200-mcu
MAX_STEPS=1000000
```

Run one test:

```sh
make -C smallc-microcpu test TEST=015_locals_while
```

Run one test with instruction trace saved to its log:

```sh
make -C smallc-microcpu test TEST=015_locals_while TRACE=1
```

Generated assembly, binaries, and logs are kept under
`smallc-microcpu/build/tests/` after `make test` so the output can be inspected
directly.

## Self-hosting smoke checks

The port is not self-hosting yet.  A non-default smoke target checks source
compatibility by compiling selected compiler implementation files to microasm:

```sh
make -C smallc-microcpu selfhost-smoke
```

The target writes generated `.asm` files, full logs, and
`build/selfhost-smoke/report.txt`.  It does not assemble, link, or run the
compiler on microcpu.  By default this is report-only and exits 0 even when
compiler source files hit unsupported syntax.  Use strict mode when a failure
should fail the make target:

```sh
make -C smallc-microcpu selfhost-smoke STRICT=1
```

Known blockers and the self-hosting coding rules are tracked in
`docs/SELFHOST.md`.

## ABI

The ABI is documented in `docs/ABI.md`.  In short: `int`, `unsigned`, and
pointers are 16-bit values; plain `char` is unsigned 8-bit; `v0` is the return
value and expression accumulator; `v4` is the frame pointer; `sp` grows
downward; callers push arguments left to right and remove them after the call.

## Backend Scope

The current backend is intentionally small and supports:

- `int main()`
- K&R-style and simple ANSI-style function argument declarations
- constants and local/global `int` variables
- local/global unsigned plain `char`
- assignment and return values
- unary `-`, `!`, and `~`
- arithmetic, bitwise, and shift operators: `+`, `-`, `*`, `/`, `%`, `&`, `|`,
  `^`, `<<`, `>>`
- short-circuit logical operators: `&&`, `||`
- compound assignments: `+=`, `-=`, `&=`, `|=`, `^=`, `<<=`, `>>=`
- pre/post increment and decrement
- `if`/`else`
- `while`
- `for` and `do`/`while`
- `break` and `continue`
- `goto` and labels
- `switch`, `case`, `default`, `break` from switch, and case fallthrough
- simple `enum` constants with implicit and explicit integer values
- simple `typedef` aliases for `int`, `char`, pointers, and named structs
- direct function calls, nested calls, and calls using locals/globals
- integer comparisons: `==`, `!=`, `<`, `<=`, `>`, `>=`
- basic `int *`: address of global `int`, dereference, store through pointer
- address of local variables
- global and local `int` arrays and indexing
- scaled `int *` arithmetic and `p[i]` syntax
- global and local `char` arrays
- `char *` indexing and stores
- named `struct` declarations with `int`, `char`, pointer fields, field access
  with `.`, pointer field access with `->`, and `sizeof(struct Tag)`
- global/local struct variables, arrays of structs, and pointer arithmetic over
  struct element size
- global scalar and array initializers
- char arrays initialized from strings
- zero-terminated string literals and escapes: `\n`, `\r`, `\t`, octal
  escapes including `\0`, `\\`, and `\"`
- `sizeof` for `char`, `int`, pointers, and arrays
- tiny libc string/memory helpers through `runtime/string.asm`: `strlen`,
  `memset`, `memcpy`, `memcmp`, `strcpy`, `strcmp`, and `strchr`
- tiny UART stdio helpers through `runtime/uart.asm`: `putchar`, `puts`, and
  `getchar`
- multiply, divide, and modulo through runtime helpers

Multiply, divide, modulo, comparisons, and variable shifts are emitted as calls
to simple helpers in `runtime/lib16.asm`.  The target memory model is
byte-addressed: `int` and pointers are 2 bytes, `char` is 1 byte, `int *`
arithmetic advances by 2 bytes, and `char *` arithmetic advances by 1 byte.
Struct fields are byte-addressed; `char` fields use 1 byte, `int` and pointer
fields align to 2 bytes, and struct size is rounded to 2 bytes.  Arrays of
structs use `sizeof(struct Tag)` as their element stride.
Return values are compared as raw 16-bit `V0`; for example, `-5` is `65531`.
Right shift is currently arithmetic.

Current fixed compiler metadata limits are `MAXTYPEDEFS=40`, `MAXSTRUCTS=20`,
and `MAXFIELDS=160`.

The current Small-C frontend does not provide a real `void`/`void *` type, so
memory helpers are declared in tests with temporary compatible prototypes such
as `char *memset(char *s, int c, int n);` and
`char *memcpy(char *dst, char *src, int n);`.  `memcpy` does not support
overlapping regions; add `memmove` separately when overlap is needed.
The UART helpers use temporary Small-C-compatible prototypes:
`int putchar(int c);`, `int puts(char *s);`, and `int getchar();`.
`putchar` writes the low 8 bits and returns that byte as an unsigned value.
`puts` writes the string followed by `\n` and returns 0.  `getchar` spins until
a UART RX byte is available and returns it as an unsigned 8-bit value.

Intentionally unsupported at this stage:

- unions, bitfields, anonymous struct typedefs, nested anonymous structs, and
  flexible arrays
- struct assignment by value, passing structs by value, and functions returning
  structs
- struct initializers
- `long`, `float`, and full libc
- optimizer/register allocator
- function pointers
- `void` and `void *` type semantics
- `memmove`, `printf`, `scanf`, UART line buffering, `malloc`, and `free`
- hexadecimal `\xHH` string escapes
- self-hosting
- full libc beyond the current small runtime helpers

Generated assembly includes:

```asm
include ../../../asm/include/pseudo.inc
include ../../runtime/microcpu_cc.inc
```

The output is regular microasm source and is meant to stay readable while the
port is brought up.

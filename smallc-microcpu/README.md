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
it with `../asm/microasm -binary`, runs it on `../microemu/microemu`, and checks
`V0` (`r3` in the emulator register dump) against `tests/expected.txt`.
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

The normal test flow still assembles each generated file straight to a binary.
The optional object/linker flow uses the newer microasm object format and
microlink:

```sh
make -C smallc-microcpu test-object
make -C smallc-microcpu test OBJECT_MODE=1
```

Multi-file tests live under `tests-multi/` and always use the object/linker
flow:

```sh
make -C smallc-microcpu test-multi
```

## Self-hosting smoke checks

The port is not self-hosting yet.  A non-default smoke target checks source
compatibility by compiling selected compiler implementation files to microasm:

```sh
make -C smallc-microcpu selfhost-smoke
```

The target writes generated `.asm` files, full logs, and
`build/selfhost-smoke/report.txt`.  The report includes the first blocker,
symbol/macro/include usage, the include files seen by the smoke runner, and an
approximate declaration-source breakdown.  It does not assemble, link, or run
the compiler on microcpu.  By default this is report-only and exits 0 even when
compiler source files hit unsupported syntax.  Use strict mode when a failure
should fail the make target:

```sh
make -C smallc-microcpu selfhost-smoke STRICT=1
```

The smoke target can also ask the compiler for object-ready assembly and then
assemble every successful translation unit to `.o`:

```sh
make -C smallc-microcpu selfhost-smoke OBJECT_MODE=1
```

Known blockers and the self-hosting coding rules are tracked in
`docs/SELFHOST.md`.

## Minimal Preprocessor

The compiler has a deliberately small preprocessing layer.  It supports:

- `#include "file.h"` with search in the current source directory, then `-I`
  paths, then the controlled compatibility headers
- `#include <file.h>` with search in `-I` paths, then the controlled
  compatibility headers
- `-I DIR` and `-IDIR`
- `-D NAME`, `-DNAME`, and `-DNAME=value` for simple object-like defines
- nested includes up to `MAXINCLUDE`
- object-like `#define NAME value` and `#define NAME`
- simple function-like `#define NAME(a,b) replacement` macros
- `#undef NAME`
- header-guard style `#ifdef`, `#ifndef`, `#else`, and `#endif`
- block comments with `/* ... */`

Function-like macro definitions must use the old C form with no whitespace
between the macro name and `(`.  Invocations may have whitespace before `(`.
Arguments support nested parentheses, string literals, and character literals.

This is not a full ANSI C preprocessor.  Macro stringification (`#`), token
pasting (`##`), variadic macros, predefined macros such as `__FILE__`, and full
`#if` expressions are unsupported.  Recursive expansion is capped by
`MAXMACEXPAND`, and system include directories are not searched by default.
The controlled headers under `smallc-microcpu/include/` are small compatibility
shims for smoke checks, not a hosted libc.

## ABI

The ABI is documented in `docs/ABI.md`.  In short: `int`, `unsigned`, and
pointers are 16-bit values; plain `char` is unsigned 8-bit; `v0` is the return
value and expression accumulator; `v4` is the frame pointer; `sp` grows
downward; callers push arguments left to right and remove them after the call.

## Backend Scope

The current backend is intentionally small and supports:

- `int main()`
- K&R-style and simple ANSI-style function argument declarations
- typedef names in K&R-style function argument declarations
- simple multiline ANSI-style function definitions
- constants and local/global `int` variables
- local/global unsigned plain `char`
- 31 significant identifier characters
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
- minimal preprocessing: object-like and simple function-like `#define`,
  `#undef`, guarded includes, `#ifdef`/`#ifndef`, and `-I` include paths
- direct function calls, nested calls, calls using locals/globals, and minimal
  indirect calls through function-pointer arguments
- repeated compatible function prototypes, prototypes before definitions, and
  multiline prototypes
- `void` function return type, `void` parameter lists, and plain `return;`
- file-scope `static` globals, `static` functions, and static prototypes
- `extern` declarations for object/linker builds
- ignored `const` qualifiers for compatibility declarations
- integer comparisons: `==`, `!=`, `<`, `<=`, `>`, `>=`
- basic `int *`: address of global `int`, dereference, store through pointer
- pointer depth greater than one, including `char **`, `int **`, pointer arrays,
  and pointer-to-pointer dereference/store
- basic casts between scalar and pointer-shaped types for compatibility code
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
- `sizeof` for `char`, `int`, pointers, arrays, and dereferenced pointer
  expressions such as `sizeof(*p)`
- tiny libc string/memory helpers through `runtime/string.asm`: `strlen`,
  `memset`, `memcpy`, `memcmp`, `strcpy`, `strcmp`, and `strchr`
- tiny UART stdio helpers through `runtime/uart.asm`: `putchar`, `puts`, and
  `getchar`
- multiply, divide, and modulo through runtime helpers
- optional object/linker test flow and small multi-file test programs

Multiply, divide, modulo, comparisons, and variable shifts are emitted as calls
to simple helpers in `runtime/lib16.asm`.  The target memory model is
byte-addressed: `int` and pointers are 2 bytes, `char` is 1 byte, `int *`
arithmetic advances by 2 bytes, and `char *` arithmetic advances by 1 byte.
Struct fields are byte-addressed; `char` fields use 1 byte, `int` and pointer
fields align to 2 bytes, and struct size is rounded to 2 bytes.  Arrays of
structs use `sizeof(struct Tag)` as their element stride.
Return values are compared as raw 16-bit `V0`; for example, `-5` is `65531`.
Right shift is currently arithmetic.

Current fixed compiler metadata limits are `NUMGLBS=300`, `NUMLOCS=25`,
`LITABSZ=8192`, `MACNBR=300`, `MAXINCLUDE=8`, `MAXTYPEDEFS=40`,
`MAXSTRUCTS=20`, and `MAXFIELDS=160`.  Symbol names are significant to 31
characters.  The limit is 31, not 63, because the original variable-length
local symbol table stores a binary name length that must stay below ASCII
space.  In object mode, externally visible assembler names longer than the
microasm object-file symbol limit are shortened with a deterministic hash and
collision suffix.  The global-symbol limit was raised after the self-host
report showed real `cc1.c` pressure with no repeated includes and controlled
headers already minimized.

The current Small-C frontend supports `void` for function return types and
`foo(void)` parameter lists.  `void *` is accepted as a pointer-sized
compatibility type for simple declarations, calls, and casts, but it is not a
fully distinct checked type yet.  `memcpy` does not support overlapping
regions; add `memmove` separately when overlap is needed.
The UART helpers use temporary Small-C-compatible prototypes:
`int putchar(int c);`, `int puts(char *s);`, and `int getchar();`.
`putchar` writes the low 8 bits and returns that byte as an unsigned value.
`puts` writes the string followed by `\n` and returns 0.  `getchar` spins until
a UART RX byte is available and returns it as an unsigned 8-bit value.

`const` is currently parsed as a compatibility qualifier only.  It does not
place data in a read-only segment and assignments to `const` objects are not
diagnosed yet.

Intentionally unsupported at this stage:

- unions, bitfields, anonymous struct typedefs, nested anonymous structs, and
  flexible arrays
- struct assignment by value, passing structs by value, and functions returning
  structs
- struct initializers
- `long`, `float`, and full libc
- optimizer/register allocator
- full function pointer semantics beyond simple indirect calls
- full `void *` type checking semantics
- `memmove`, `printf`, `scanf`, UART line buffering, `malloc`, and `free`
- macro stringification, token pasting, variadic macros, predefined macros,
  and full `#if` preprocessor expressions
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

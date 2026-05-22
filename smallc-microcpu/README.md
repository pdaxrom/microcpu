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
- direct function calls, nested calls, and calls using locals/globals
- integer comparisons: `==`, `!=`, `<`, `<=`, `>`, `>=`
- basic `int *`: address of global `int`, dereference, store through pointer
- address of local variables
- global and local `int` arrays and indexing
- scaled `int *` arithmetic and `p[i]` syntax
- global and local `char` arrays
- `char *` indexing and stores
- zero-terminated string literals
- `strlen(char *)` through `runtime/string.asm`
- multiply, divide, and modulo through runtime helpers

Multiply, divide, modulo, comparisons, and variable shifts are emitted as calls
to simple helpers in `runtime/lib16.asm`.  The target memory model is
byte-addressed: `int` and pointers are 2 bytes, `char` is 1 byte, `int *`
arithmetic advances by 2 bytes, and `char *` arithmetic advances by 1 byte.
Return values are compared as raw 16-bit `V0`; for example, `-5` is `65531`.
Right shift is currently arithmetic.

Intentionally unsupported at this stage:

- structs, unions, typedefs, enums
- `long`, `float`, and full libc
- optimizer/register allocator
- self-hosting
- full libc beyond the current small runtime helpers

Generated assembly includes:

```asm
include ../../../asm/include/pseudo.inc
include ../../runtime/microcpu_cc.inc
```

The output is regular microasm source and is meant to stay readable while the
port is brought up.

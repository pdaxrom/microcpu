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

The test target compiles every `tests/*.c` file to readable microasm,
assembles it with `../asm/microasm`, runs it on `../microemu/microemu` when the
emulator is present, and checks `V0` (`r3` in the emulator register dump)
against `tests/expected.txt`.

Generated assembly is kept under `smallc-microcpu/build/*.asm` after
`make test` so the output can be inspected directly.

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
- addition/subtraction and bitwise operations
- `if`/`else`
- `while`
- direct function calls, nested calls, and calls using locals/globals
- integer comparisons: `==`, `!=`, `<`, `<=`, `>`, `>=`
- basic `int *`: address of global `int`, dereference, store through pointer
- global `int` arrays and indexing
- multiply, divide, and modulo through runtime helpers

Multiply, divide, modulo, comparisons, and variable shifts are emitted as calls
to simple helpers in `runtime/lib16.asm`.

Intentionally unsupported at this stage:

- structs, unions, typedefs, enums
- `long`, `float`, and full libc
- optimizer/register allocator
- local arrays
- self-hosting
- broad string-literal/libc workflows

Generated assembly includes:

```asm
include ../../asm/include/pseudo.inc
include ../runtime/microcpu_cc.inc
```

The output is regular microasm source and is meant to stay readable while the
port is brought up.

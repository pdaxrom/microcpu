# Small-C for microcpu

This is an initial microcpu backend for James E. Hendrix Small-C 2.2,
Revision Level 117.  The untouched baseline imported from the DosWorld
repository is kept under `original/C/`; the buildable port is under `src/`.
Original copyright notices are preserved in the copied source files.

## Build

```sh
make -C smallc-microcpu
```

Compile and verify the initial tests:

```sh
make -C smallc-microcpu test
```

The test target compiles each `tests/*.c` file to readable microasm, assembles
it with `../asm/microasm`, runs it on `../microemu/microemu`, and checks `V0`
(`r3` in the emulator register dump).

## ABI

- `int`, `unsigned`, and pointers are 16-bit values.
- `char` is stored in the low byte of a 16-bit register or word.
- Return value and expression primary register: `v0`.
- Secondary expression register: `v1`.
- Scratch registers: `v2`, `v3`.
- Frame pointer: `v4`.
- Stack pointer: `sp`.
- Return link: `lr`.
- Function arguments are pushed by the caller, left to right as in the
  original Small-C calling sequence; offsets match the Hendrix frame model.
- The callee saves `lr` and the old `v4`, then uses `v4` as the frame pointer.
- The caller removes arguments after a call.

## Backend Scope

The current backend is intentionally small and targets the first validation
subset:

- `int main()`
- constants and local/global `int` variables
- assignment
- addition/subtraction and bitwise operations
- `if`/`else`
- `while`
- direct function calls with 0..2 arguments
- global `int` variables

Multiply, divide, modulo, comparisons, and variable shifts are emitted as calls
to simple helpers in `runtime/lib16.asm`.

Generated assembly includes:

```asm
include ../../asm/include/pseudo.inc
include ../runtime/microcpu_cc.inc
```

The output is regular microasm source and is meant to stay readable while the
port is brought up.

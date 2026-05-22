# microcpu Small-C ABI

This document describes the ABI emitted by the Hendrix Small-C 2.2
Revision Level 117 microcpu backend.  It documents the generated code as it
exists now; future backend changes must update this file.

## Data Model

- `int`: 16-bit signed two's-complement value.
- `unsigned`: 16-bit unsigned value.
- `char`: 8-bit value.
- Plain `char`: unsigned 8-bit value.  Loads zero-extend to 16 bits.
- Pointer: 16-bit byte address.
- `sizeof(int) == 2`, `sizeof(unsigned) == 2`, `sizeof(char) == 1`,
  `sizeof(pointer) == 2`.
- The target memory is byte-addressed.  Word loads and stores use two
  little-endian bytes.  Byte loads and stores use `ldrl` and `strl`.
- `int *` arithmetic is scaled by 2 bytes, so `p + 1` points to the next
  16-bit `int`.  `char *` arithmetic is scaled by 1 byte.
- `int` arrays use 2 bytes per element.  `char` arrays use 1 byte per element.

## Registers

- `pc`: program counter.
- `sp`: stack pointer.
- `lr`: link/return register.
- `v0`: expression accumulator and return value.
- `v1`: secondary expression register and left operand after expression stack
  pops.
- `v2`, `v3`: scratch registers used by generated code and runtime helpers.
- `v4`: frame pointer for generated Small-C functions.

`v0`, `v1`, `v2`, and `v3` are caller-saved.  `lr` is saved by every generated
callee before it makes nested calls.  `v4` is callee-saved by the generated
function prologue.

## Stack

The stack grows downward.  A push stores at `[sp]` and then subtracts 2 from
`sp`; a pop adds 2 to `sp` and then loads from `[sp]`.

Function arguments are pushed by the caller in source order, left to right, to
match the original Small-C calling sequence.  The caller removes the arguments
after the call.

## Stack Frame

Generated function prologue:

```asm
str lr, sp, 0
sub sp, sp, 2
str v4, sp, 0
mov v4, sp
sub sp, sp, 2
```

After the prologue:

```text
v4 + 0  saved caller v4
v4 + 2  saved lr
v4 + 4  last argument
v4 + 6  previous argument
...
v4 - 2  first 16-bit local, or the high end of a larger local object
v4 - 4  next 16-bit local, or earlier bytes in a larger local object
```

Local variables are allocated by subtracting their byte size from `sp` after
the prologue.  `int` locals consume 2 bytes.  `char` locals consume 1 byte and
are accessed with byte load/store instructions.  Local arrays are allocated as
one contiguous downward-growing block, and the symbol address points at the
lowest byte address in that block.

Generated function epilogue:

```asm
mov sp, v4
ldr v4, sp, 0
add sp, sp, 2
ldr lr, sp, 0
mov pc, lr
```

The caller then adds the argument byte count to `sp`.

## Symbols

Small-C external names are emitted with a leading underscore.  For example,
the C function `main` is emitted as `_main`, and a global variable `g` is
emitted as `_g`.

Compiler-generated numeric labels use the form `_<number>`.  Literal/string
data labels use the same numeric label space.  String literals are emitted as
zero-terminated byte data in the function's literal pool.

## Runtime Helpers

Runtime helpers follow the expression-register convention:

- Input left operand: `v0`.
- Input right/secondary operand: `v1`.
- Result: `v0`.
- Scratch: `v2`, `v3`.
- Helpers that call other helpers save and restore `lr`.

Current helpers live in `runtime/lib16.asm`.

String helpers live in `runtime/string.asm`.  `_strlen` is callable as the C
function `int strlen(char *s);`; it reads its single stack argument according
to the normal calling convention and returns the byte length in `v0`.

## Test Startup And Halt

The generated test crt0 starts at load address 0:

```asm
__smallc_start:
set sp, __smallc_stack_top
jsr _main
__test_halt:
b __test_halt
```

`_main` returns its value in `v0`.  The halt path does not modify `v0`, so the
test runner can execute the binary under `microemu --stop-on-self-branch` and
compare the final dumped `v0`/`r3` value.  The compiler appends a 512-byte
stack block after the generated program and initializes `sp` to
`__smallc_stack_top`.

# microcpu Small-C ABI

This document describes the ABI emitted by the Hendrix Small-C 2.2
Revision Level 117 microcpu backend.  It documents the generated code as it
exists now; future backend changes must update this file.

## Data Model

- `int`: 16-bit signed two's-complement value.
- `unsigned`: 16-bit unsigned value.
- `char`: 8-bit value.
- `void`: supported as a function return type and as an empty parameter list
  marker in declarations such as `f(void)`.  `void *` is currently accepted as
  a pointer-sized compatibility type, but the compiler does not enforce full
  C `void *` type rules.
- Plain `char`: unsigned 8-bit value.  Loads zero-extend to 16 bits.
- Pointer: 16-bit byte address.
- Pointer depth is represented by repeated 16-bit pointer objects.  For
  example, `char **` is a pointer to a 16-bit cell that itself contains a byte
  address.
- `sizeof(int) == 2`, `sizeof(unsigned) == 2`, `sizeof(char) == 1`,
  `sizeof(pointer) == 2`.
- `sizeof` on arrays returns the byte size of the whole array object.
  `sizeof(*p)` is supported for pointer expressions and returns the byte size
  of the pointed-to object.
- The target memory is byte-addressed.  Word loads and stores use two
  little-endian bytes.  Byte loads and stores use `ldrl` and `strl`.
- `int *` arithmetic is scaled by 2 bytes, so `p + 1` points to the next
  16-bit `int`.  `char *` arithmetic is scaled by 1 byte.  Pointer-to-pointer
  arithmetic is scaled by 2 bytes, the size of a pointer cell.
- `int` arrays use 2 bytes per element.  `char` arrays use 1 byte per element.
- `struct` fields are laid out in declaration order.  `char` fields have size
  and alignment 1.  `int`, pointer, and struct fields align to 2 bytes.  The
  final struct size is rounded up to 2 bytes.
- Arrays of structs use `sizeof(struct Tag)` as the element stride.  Pointer
  arithmetic on `struct Tag *` is scaled by that same size.
- Return values are the raw 16-bit contents of `v0`.  Negative `int` results
  therefore appear as their unsigned two's-complement representation in tests;
  for example, `-5` is dumped and compared as `65531`.

`enum` constants are compile-time `int` constants.  The enum type itself is
currently treated as `int` when used as a declaration type.  `typedef` names
are compile-time aliases for the recorded base type plus pointer/non-pointer
declarator shape; they do not create distinct ABI types.

`const` is currently accepted as a source-compatibility qualifier and ignored
for storage and code generation.  It does not imply read-only placement and is
not enforced by assignment diagnostics yet.

Simple C-style casts are accepted for scalar and pointer-shaped values.  They
adjust the compiler's expression type metadata, but do not emit numeric
conversion code beyond the ordinary expression load.

Identifiers are significant to 31 characters in the compiler symbol tables.

## Expression Results

- Logical operators and logical negation return integer `0` or `1`.
- `&&` and `||` use C short-circuit evaluation; the skipped operand is not
  evaluated and its side effects do not occur.
- Left shift uses 16-bit arithmetic modulo the target word size.
- Right shift currently uses the backend's arithmetic shift helper (`__sar16`),
  so the sign bit is preserved.  A separate logical right shift for `unsigned`
  is not emitted yet.

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

`void` functions use the same call and return sequence as `int` functions.
They do not define a meaningful `v0` value on return.  A plain `return;`
emits the normal function epilogue without preparing `v0`.

For leaf runtime functions that do not build a generated Small-C frame, the
last argument is at `sp + 2`, the previous argument is at `sp + 4`, and so on.
For example, `memset(s, c, n)` sees `n` at `sp + 2`, `c` at `sp + 4`, and `s`
at `sp + 6`.

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

In object mode, non-static definitions emit microasm `public` entries and
unresolved `extern` declarations are left for `microlink`.  File-scope
`static` variables and functions are emitted as object-local labels and are not
marked `public`.  If an externally visible assembler symbol would exceed the
current object-file symbol-name limit, the backend emits a deterministic
shortened form consisting of the leading underscore, a readable prefix, and a
hash suffix plus a collision suffix.  Definitions and references use the same
shortened name, and colliding long names are assigned different object symbols.

Compiler-generated numeric labels use the form `_<number>`.  Literal/string
data labels use the same numeric label space.  String literals are emitted as
zero-terminated byte data in the function's literal pool.

## Initialized Data

Global `int` data is emitted as little-endian 16-bit words with `dw`.  Global
`char` data is emitted as bytes with `db`.  Default-initialized storage is
emitted with `ds`.

Global scalar and array initializers are laid out in declaration order.
`char s[] = "ABC";` emits four bytes: `65, 66, 67, 0`, and the recorded array
size is 4 bytes.  String literals used in expressions are emitted in the
function literal pool and are also zero-terminated.

Default-initialized structs and arrays of structs reserve zeroed byte storage
with `ds`.  Global struct initializers are not implemented yet.

Supported string escapes are `\n`, `\r`, `\t`, `\b`, `\f`, octal escapes
including `\0`, and escaped ordinary characters such as `\\` and `\"`.
Hexadecimal `\xHH` escapes are not supported yet.

## Switch

`switch` evaluates the controlling expression into `v0`, then calls
`__switch`.  The compiler emits a linear table of case-label addresses and
case values after the switch body.  `__switch` scans that table and transfers
control to the first matching case label, or returns to the default/no-match
path when no case matches.  Cases therefore retain normal C fallthrough
semantics, and `break` exits the current switch.

## Runtime Helpers

Runtime helpers follow the expression-register convention:

- Input left operand: `v0`.
- Input right/secondary operand: `v1`.
- Result: `v0`.
- Scratch: `v2`, `v3`.
- Helpers that call other helpers save and restore `lr`.
- Runtime helpers may clobber `v0`, `v1`, `v2`, and `v3`.  Helpers that use
  `v4` save and restore it.

Current helpers live in `runtime/lib16.asm`.

String and memory helpers live in `runtime/string.asm` and use the same leading
underscore as generated external C symbols:

- `_strlen`: `int strlen(char *s);`
- `_memset`: currently declared as `char *memset(char *s, int c, int n);`
- `_memcpy`: currently declared as
  `char *memcpy(char *dst, char *src, int n);`
- `_memcmp`: `int memcmp(char *a, char *b, int n);`
- `_strcpy`: `char *strcpy(char *dst, char *src);`
- `_strcmp`: `int strcmp(char *a, char *b);`
- `_strchr`: `char *strchr(char *s, int c);`

Pointer-returning helpers return the pointer value in `v0`.  `memcmp` and
`strcmp` compare bytes as unsigned 8-bit values; equality returns 0, and for
non-equal inputs only the sign of the result is specified.  `memcpy` does not
define overlapping-copy behavior.

UART stdio helpers live in `runtime/uart.asm`, use the `hc1200-mcu` UART at
byte address `$ffe0`, and follow the same leading-underscore symbol convention:

- `_putchar`: `int putchar(int c);`
- `_puts`: `int puts(char *s);`
- `_getchar`: `int getchar();`

`putchar` writes the low 8 bits of `c` to UART TX and returns that unsigned
byte in `v0`.  `puts` writes bytes until the terminating NUL, writes a single
line feed byte (`'\n'`, value 10), and returns 0 in `v0`.  `getchar` blocks by
spinning on the UART RX status bit until a byte is available, then returns that
byte zero-extended in `v0`.  These helpers may clobber `v0`, `v1`, `v2`, and
`v3`; they do not use `v4`.

## Object And Linker Flow

The direct test flow emits one self-contained assembly file.  Object mode emits
only the compiled translation unit and expects the test runner or build system
to assemble and link runtime objects.

The current object test link order is:

```text
runtime/crt0_object.o
program translation-unit objects
runtime/runtime_object.o
runtime/stack_object.o
```

`crt0_object.o` defines the startup code and calls `_main`.
`runtime_object.o` exports arithmetic, comparison, switch, string/memory, and
UART helper routines.  `stack_object.o` provides the test stack symbol
`__sc_stktop`.

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

In object-mode tests, the equivalent startup uses the shorter exported stack
symbol `__sc_stktop` because the current object format limits symbol names.

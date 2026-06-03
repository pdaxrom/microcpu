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
Object-mode generated jumps use the `jmp` macro form for compiler-emitted
branches so large translation units are not constrained by the short relative
range of the raw `b` instruction.

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

## Experimental P-code VM

The experimental p-code backend is an alternative compiler backend, not the
default ABI for native generated code.  It lowers the existing internal
register-oriented pseudo-code into an external stack VM.

P-code data model:

- Instruction stream: 8-bit opcodes with 0 or more byte operands.
- 16-bit operands are little-endian low byte then high byte.
- VM stack cell: 16 bits.
- `int` and pointers: 16-bit VM cells.
- `char` memory: byte-addressed and zero-extended on load.
- Bytecode fetch is byte-by-byte, so bytecode does not require word alignment.

The first host interpreter keeps a p-code operand stack plus per-call frame
temporary/local slots.  The backend maps the internal primary and secondary
register values to reserved frame temporary slots, then materializes those
slots onto the VM stack when emitting stack operations.  The optional p-code
compaction pass keeps the same ABI and currently performs only local safe
bytecode rewrites plus compact opcode selection, including immediate
`ADDI_S8`, `ADDI_U16`, `SUBI_S8`, `EQI_S8`, temp store-immediate
`SLOCAL0_S8`/`SLOCAL2_S8`, and zero-local `ZLOCAL_*` forms.

P-code direct calls use the same source-order argument convention as the native
ABI.  The caller pushes argument values in source order; the interpreter maps
the last argument to frame offset 4, the previous argument to offset 6, and so
on, matching the native generated frame layout.  `RET` leaves the function
result as a 16-bit VM cell.

P-code function pointers to p-code functions are 16-bit linked bytecode entry
addresses in the microcpu object path.  `ICALL_U8` expects the target address
on top of the p-code stack with arguments below it in the same order used by
direct calls.  The interpreter pops the target, builds a normal p-code frame,
transfers the arguments, and pushes the return value after `RET`.  Function
pointers to native `NCALL` entries are not part of the current ABI.

Native p-code calls use `NCALL` with the normal p-code argument convention.
Host p-code tests still use compact native-table ids.  The microcpu object path
uses `NCALL_ADDR_U16`, which stores an argument count byte followed by a
relocatable 16-bit native function address.  Calls with 0, 1, 2, or 3 arguments
use the shorter `NCALL0_ADDR_U16`, `NCALL1_ADDR_U16`, `NCALL2_ADDR_U16`, or
`NCALL3_ADDR_U16` forms, which omit the explicit argument-count byte.  For each
native call, the
interpreter pops p-code arguments, rebuilds the ordinary native source-order
argument stack, calls the native symbol, restores interpreter state, and pushes
the 16-bit `v0` return value onto the p-code stack.  Native callees may use
normal global data and may return pointers to native or p-code data; p-code
global-address operands in the microcpu object path are linked absolute target
addresses.

For p-code selfhost execution smoke, `runtime/hosted_io.asm` provides a tiny
native hosted-service ABI through ordinary p-code native-call entries.  It is
linked before the p-code objects and uses the same native source-order argument
stack: for an N-argument native call, argument 1 is deepest on the stack and
argument N is at `SP+2`.  The service maps `_stdin`, `_stdout`, and `_stderr`
to small integer handles, implements UART-backed `_fgetc`, `_fgets`, `_fputc`,
and `_fputs`, treats UART RX byte `0x04` as EOF, and provides a bump `_calloc`
that starts after the generated `__pcd_gend` end-marker symbol.  `_calloc`
halts in a self-branch with
`V0=0xca10` if the allocation would pass the hosted heap guard or wrap the
16-bit address space.  `_fopen` is currently a smoke stub that returns 0; no
filesystem ABI is defined yet.

The hosted smoke runtime exports object-safe diagnostic aliases for the runner:
`__hst_lasterr`, `__hst_allocsz`, `__hst_hstart`, `__hst_hcur`, `__hst_hend`,
`__hst_service`, and `__hst_fhandle`.  These correspond to
`__hosted_last_error`, `__hosted_last_alloc_size`, `__hosted_heap_start`,
`__hosted_heap_cur`, `__hosted_heap_end`, `__hosted_fail_service`, and
`__hosted_fail_file_handle` in the smoke report.  On heap exhaustion the runtime
also emits a UART diagnostic line:

```text
HD <error> <requested-size> <heap-current> <heap-start> <heap-end> <service>
```

Service id `1` currently means `_calloc`.

For microcpu p-code tests the linked image starts in
`runtime/pcode_interpreter.asm`.  When p-code `main` returns, the interpreter
places the final 16-bit result in native `v0` and branches to the usual
`__test_halt` self-branch.  The current interpreter uses fixed internal areas:
512 bytes for the p-code operand stack, 16 call frames, and 64 bytes per
p-code frame.  For memory-map diagnostics it exports `__pcd_vstk`,
`__pcd_vstkend`, `__pcd_frames`, `__pcd_frame0`, `__pcd_frameend`,
`__pcd_nstk`, and `__pcd_nstktop`.  The object-format-visible entry symbol is
`__pcode_entry`,
defined only by the p-code object that contains `main`; it contains a word
relocation to the linked p-code `_main` address.  P-code objects do not define
duplicate `__pcode_start`/`__pcode_end` symbols.  Public and external p-code
object symbols are shortened deterministically when needed to satisfy the
15-character microasm object format limit.

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

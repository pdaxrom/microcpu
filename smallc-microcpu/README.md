# Small-C for microcpu

This is an initial microcpu backend for James E. Hendrix Small-C 2.2,
Revision Level 117.  The untouched baseline imported from the DosWorld
repository is kept under `original/C/`; the buildable port is under `src/`.
Original copyright notices are preserved in the copied source files.
The buildable port is microcpu-only; the legacy 8086 code-generation fallback
has been removed from `src/`.

## Build

```sh
make -C smallc-microcpu
```

Compile and verify the tests:

```sh
make -C smallc-microcpu test
```

The build produces two host tools, `build/smallcpp` and `build/smallcc`.
The split source layout is canonical for every build path: host tests,
object-mode tests, and self-host smoke all compile the same `smallcpp_*`,
`smallcc_*`, and shared compiler modules.  The old monolithic `cc1.c` path is
not used for normal builds.

The test target runs the full split pipeline for every `tests/*.c` file:

```text
smallcpp source.c -I include -I tests/include -o build/source.i
smallcc build/source.i -o build/source.asm
microasm source.asm -> source.bin
microemu source.bin
```

It then checks `V0` (`r3` in the emulator register dump) against
`tests/expected.txt`.  Tests listed in `tests/expected_uart.txt` also compare
UART TX output, and tests listed in `tests/input_uart.txt` preload UART RX
using `microemu --uart-rx`.

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

The normal test flow assembles each generated file straight to a binary after
preprocessing and compilation.  The optional object/linker flow uses the newer
microasm object format and microlink:

```sh
make -C smallc-microcpu test-object
make -C smallc-microcpu test OBJECT_MODE=1
```

Multi-file tests live under `tests-multi/` and always use the object/linker
flow:

```sh
make -C smallc-microcpu test-multi
```

## Experimental p-code backend

The native microcpu backend remains the default.  An experimental backend can
emit an external stack-VM p-code form instead:

```sh
smallcc --backend pcode build/source.i -o build/source.pca
```

This first implementation is intentionally a lowering layer from the existing
register-oriented internal pseudo-code to an external 8-bit bytecode VM.  It
does not rewrite the frontend into a stack-machine compiler.  Unsupported
internal opcodes fail explicitly with:

```text
unsupported internal pcode for stack backend: <opcode>
```

The host interpreter encodes the textual `.pca` into compact bytecode and runs
it with 16-bit VM cells:

```sh
make -C smallc-microcpu test-pcode-host
```

P-code compaction is enabled for p-code test and self-host smoke targets by
default.  Use `PCODE_OPT=0` to keep the raw lowering output for debugging:

```sh
make -C smallc-microcpu test-pcode-host PCODE_OPT=0
make -C smallc-microcpu test-pcode-microemu PCODE_OPT=0
```

The microcpu-side interpreter links the bytecode object after the interpreter
and optional runtime/native objects, then runs the result under `microemu`:

```sh
make -C smallc-microcpu test-pcode-microemu
```

P-code can also call user-provided native object files.  The native-call test
suite builds p-code `main.c` files, compiles sibling C files with the native
microcpu backend, links them between the runtime and `pcode.o`, and executes
the result under `microemu`:

```sh
make -C smallc-microcpu test-pcode-native
```

P-code also has a multi-module test path that assembles each translation unit
to its own p-code object, links those objects directly, then runs the image
under `microemu`:

```sh
make -C smallc-microcpu test-pcode-multi
```

The p-code test suite lives under `pcode-tests/` and currently covers return
constants, local/global variables, arithmetic, comparisons, short-circuit
logical operators, bitwise and shift operators, `if`/`else`, `while`, `switch`,
direct C calls, arrays, basic pointers, string indexing, enum/typedef basics,
simple struct access, static and void functions, pointer-to-pointer loads,
casts, pre/post increment and decrement, p-code function-pointer indirect
calls, native `strlen`/`strcpy`, and native `putchar` UART output.  The
microcpu interpreter uses the same bytecode semantics as the host interpreter
and currently supports direct relocatable native calls through
`NCALL_ADDR_U16`, including optional user native objects.  Function pointers
currently target p-code functions; native function pointers are still
unsupported.  P-code is not used by the normal native test flow yet.
`test-pcode-multi` additionally covers p-code-to-p-code cross-module calls,
extern globals, static symbol isolation, and cross-module p-code function
pointers.  Long p-code public symbols are shortened deterministically for the
15-character object format limit.

`build/pcode/size-report.txt` records raw bytecode bytes, global data bytes,
native table bytes, total p-code object data size, and a comparison with the
native backend output for each host p-code test.  `test-pcode-microemu` writes
the target-side size report to `build/pcode-microemu/size-report.txt`, and
`test-pcode-native` writes `build/pcode-native/size-report.txt`.  See
`docs/PCODE.md` for the VM encoding and link model.
Self-host p-code reports also include measurement-only peephole candidates such
as same-temp store/load pairs, constant branch opportunities, branch-to-branch
sites, and hottest local/temp slots.  These diagnostics do not change emitted
bytecode; they are there to guide the next optimizer pass.  The current p-code
optimizer removes proven-dead temp roundtrips and rewrites live non-short
same-temp store/load roundtrips to `dup`/`slocal` when that is smaller.  It
also folds simple constant branches, removes branches to the next instruction,
inverts `conditional; jmp; label` pairs, and threads branches through
intermediate `jmp` instructions when the encoded branch does not grow.  It also
rewrites `iconst <s8>; add/sub/eq` to compact `ADDI_S8`, `SUBI_S8`, and
`EQI_S8`, rewrites larger `iconst <u16>; add` pairs to `ADDI_U16`, and
rewrites common `iconst <s8>; slocal 0/2` pairs to `SLOCAL0_S8`/`SLOCAL2_S8`
when that is smaller.  It also rewrites `iconst 0; slocal <offset>` pairs to
compact `ZLOCAL_*` zero-local stores when no label targets the store.  A
common `llocal 0; llocal 2; add` lowering pattern is compacted to
`LADD_LOCAL0_2` when no label targets the removed instructions.  Live
`slocal 0; llocal 0` roundtrips are compacted to `TLOCAL0`, which stores the
top stack value while leaving it available as the expression result.
The object-mode encoder uses
compact `NCALL0/1/2/3_ADDR_U16` forms for common native calls with 0, 1, 2, or
3 arguments.

To measure whether p-code helps the self-hosting size problem without trying
to run a target-hosted compiler yet:

```sh
make -C smallc-microcpu selfhost-pcode-smoke
```

This writes `build/selfhost-pcode/size-report.txt`.  The default mode is
report-only; `STRICT=1` makes unsupported p-code lowering fail the target.

To try linking separate p-code-hosted tool images without running them:

```sh
make -C smallc-microcpu selfhost-pcode-link-smoke
```

This writes `build/selfhost-pcode-link/report.txt`.  It assembles each tool
module as a separate p-code object and links those objects directly with the
p-code interpreter plus generated link-only hosted stubs.  The stubs are
placeholders for size/unresolved-symbol measurement, not real target file I/O.
With the current conservative compaction pass, this link smoke reports both
`smallcpp` and `smallcc` below the 64K binary limit; `smallcc` is still a smoke
image, not a runnable target-hosted compiler.

To run the split p-code images far enough to exercise hosted startup and
UART-backed stdio:

```sh
make -C smallc-microcpu selfhost-pcode-exec-smoke
```

This writes `build/selfhost-pcode-exec/report.txt` and
`build/selfhost-pcode-exec/memory-map.txt`, and remains report-only by default.
It links the p-code interpreter, `runtime/hosted_io.asm`, and the same direct
p-code object set used by link smoke, then runs the images on the synthetic
`hc1200-cpu` 64 KiB RAM board.  The hosted model is intentionally tiny:
`stdin`, `stdout`, and `stderr` are UART-backed, UART RX byte `0x04` is EOF,
`fopen` is still a nonfunctional smoke stub, and `calloc` is a bump allocator
after the p-code payload.  The current execution smoke reaches the compiler
banners and then halts with `V0=0xca10`, which marks hosted heap exhaustion.
The memory map reports linked object ranges, p-code bytecode/data ranges, VM
and native stack ranges, hosted heap diagnostics, and overlap checks.  The
current blocker is now classified precisely: `smallcpp` fails a 13,000-byte
`symtab` allocation after earlier table allocations, and `smallcc` fails the
8,192-byte literal pool (`litq`) allocation with about 1.4 KB left below the
hosted heap guard.  The next work is reducing runtime RAM footprint/data
layout, not p-code bytecode link size.

## Self-hosting smoke checks

The port is not self-hosting yet.  A non-default smoke target checks source
compatibility by compiling the same canonical split compiler modules used by
the host build to microasm:

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

Object mode uses the same split modules as the host tools.  There are no
selfhost-only wrapper modules and no separate monolithic host compiler source.
Object-mode code generation uses long `jmp` macro branches for compiler-sized
functions so branch displacements do not depend on short relative range.

After object smoke succeeds, a report-only link experiment can be run:

```sh
make -C smallc-microcpu selfhost-link-smoke
```

This target links the selfhost objects as two separate tool images,
`smallcpp` and `smallcc`, and writes `build/selfhost-smoke/link-report.txt`.
It is not full self-hosting and does not run either compiler stage; current
expected blockers are target-hosted file I/O/runtime support and final linked
image size work.

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
report showed real compiler frontend pressure with no repeated includes and
controlled headers already minimized.

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
- full self-hosted compiler linking/execution on the target
- full libc beyond the current small runtime helpers

Generated assembly includes:

```asm
include ../../../asm/include/pseudo.inc
include ../../runtime/microcpu_cc.inc
```

The output is regular microasm source and is meant to stay readable while the
port is brought up.

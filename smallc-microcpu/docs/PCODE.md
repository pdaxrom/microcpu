# Experimental p-code backend

This document describes the first external p-code VM used by
`smallcc --backend pcode`.  The native microcpu backend remains the default.

## Frontend strategy

The first p-code backend does not rewrite the Small-C frontend as a stack
compiler.  It translates the existing register-oriented internal pseudo-code
into an external stack VM form.  Internal primary/secondary register values are
spilled to reserved p-code frame temporary slots, then loaded onto the operand
stack as needed.  Unsupported internal opcodes produce a compiler error:

```text
unsupported internal pcode for stack backend: <opcode>
```

The current supported subset is still deliberately conservative, but now covers
more of the already-supported C frontend: constants, local/global integer
variables, assignment, arithmetic/bitwise/shift operations, comparisons,
short-circuit logical operators, `if`/`else`, `while`, `switch`, simple direct
calls, native calls, global/local int and char arrays, basic pointer operations,
string indexing, enum/typedef basics, simple struct field access, static
functions, void functions, pointer-to-pointer loads, function-pointer indirect
calls, pre/post increment and decrement, and casts used by the current tests.

## Encoding

- The bytecode stream is byte-addressed.
- Opcode size is 8 bits.
- Operands are 0 or more bytes.
- 16-bit immediates are little-endian.
- VM stack cells are 16-bit.
- `int` and pointers are 16-bit.
- `char` memory is 8-bit; byte loads zero-extend to 16-bit cells.
- The interpreter fetches operands byte-by-byte; bytecode does not require word
  alignment.

## Opcodes

| Opcode | Mnemonic | Operands |
|--------|----------|----------|
| `$00` | `NOP` | none |
| `$01` | `HALT` | none |
| `$02` | `ICONST_M1` | none |
| `$03` | `ICONST_0` | none |
| `$04` | `ICONST_1` | none |
| `$05` | `ICONST_2` | none |
| `$06` | `ICONST_S8` | signed byte |
| `$07` | `ICONST_U16` | low byte, high byte |
| `$08` | `DROP` | none |
| `$09` | `DUP` | none |
| `$0a` | `SWAP` | none |
| `$10..$13` | `LLOCAL_0..3` | none |
| `$14..$17` | `SLOCAL_0..3` | none |
| `$18` | `LLOCAL_S8` | signed byte offset |
| `$19` | `SLOCAL_S8` | signed byte offset |
| `$1a` | `LLOCAL_U16` | signed 16-bit offset |
| `$1b` | `SLOCAL_U16` | signed 16-bit offset |
| `$1c` | `ADDR_LOCAL_S8` | signed byte offset |
| `$1d` | `ADDR_LOCAL_U16` | signed 16-bit offset |
| `$20` | `LGLOBAL_U16` | 16-bit data address |
| `$21` | `SGLOBAL_U16` | 16-bit data address |
| `$22` | `ADDR_GLOBAL_U16` | 16-bit data address |
| `$30` | `LBYTE` | none |
| `$31` | `SBYTE` | none |
| `$32` | `LWORD` | none |
| `$33` | `SWORD` | none |
| `$40` | `JMP_S8` | signed byte relative offset |
| `$41` | `JMP_S16` | signed 16-bit relative offset |
| `$42` | `JZ_S8` | signed byte relative offset |
| `$43` | `JZ_S16` | signed 16-bit relative offset |
| `$44` | `JNZ_S8` | signed byte relative offset |
| `$45` | `JNZ_S16` | signed 16-bit relative offset |
| `$50` | `CALL_U16` | 16-bit p-code address, argc byte |
| `$51` | `RET` | none |
| `$52` | `ENTER_U8` | frame byte count |
| `$53` | `ENTER_U16` | frame byte count |
| `$54` | `NCALL_U8` | native id byte, argc byte |
| `$55` | `NCALL_U16` | native id word, argc byte |
| `$56` | `LEAVE` | none |
| `$57` | `ICALL_U8` | argc byte |
| `$58` | `CALL0_U16` | 16-bit p-code address |
| `$59` | `CALL1_U16` | 16-bit p-code address |
| `$5a` | `CALL2_U16` | 16-bit p-code address |
| `$60` | `ADD` | none |
| `$61` | `SUB` | none |
| `$62` | `AND` | none |
| `$63` | `OR` | none |
| `$64` | `XOR` | none |
| `$65` | `SHL` | none |
| `$66` | `SHR` | none |
| `$67` | `NEG` | none |
| `$68` | `BNOT` | none |
| `$69` | `LNOT` | none |
| `$6a` | `EQ` | none |
| `$6b` | `NE` | none |
| `$6c` | `LT` | none |
| `$6d` | `LE` | none |
| `$6e` | `GT` | none |
| `$6f` | `GE` | none |
| `$70` | `MUL` | none |
| `$71` | `UDIV` | none |
| `$72` | `UMOD` | none |
| `$73` | `SDIV` | none |
| `$74` | `SMOD` | none |

Binary operators pop the right operand first, then the left operand, and push a
16-bit result.  Comparisons push `0` or `1`.

## Textual p-code assembly

The backend currently emits readable text first.  The host interpreter encodes
that text into the byte stream above before execution.

Example:

```text
entry _main
func _main
iconst 123
slocal -30000
llocal -30000
ret
end
```

Data uses `data_label`, `data8`, `data16`, and `zero`.  Labels use `label`.
Direct calls use `call <function> <argc>`.  Native calls use
`ncall <symbol> <argc>`.  Function-address constants use
`addr_func <function>` and lower to `ICONST_U16` with the target function's
bytecode offset.  Indirect p-code calls use `icall <argc>`.

## Compaction

P-code tests and self-host p-code smoke enable conservative compaction by
default.  Disable it with:

```sh
make -C smallc-microcpu test-pcode-microemu PCODE_OPT=0
make -C smallc-microcpu selfhost-pcode-link-smoke PCODE_OPT=0
```

The current pass is deliberately local and safe:

- removes dead `slocal 0`/`llocal 0` and `slocal 2`/`llocal 2` temp
  roundtrips when a simple p-code liveness check proves the temp is not read
  before being overwritten or returning;
- keeps branch labels, function entries, and data labels as hard boundaries for
  the rewrite;
- keeps branch relaxation in the encoder, so removed instructions can make
  more `JMP`/`JZ`/`JNZ` operations use the short S8 forms;
- emits compact direct-call forms `CALL0_U16`, `CALL1_U16`, and `CALL2_U16`
  for the common 0, 1, and 2 argument cases.

The pass does not do global value numbering, constant folding, dead-code
elimination, inlining, or branch threading.  Reports include opcode
histograms, common opcode pairs, largest p-code functions, short/long branch
counts, and optimizer byte savings.

## Indirect calls

Function pointers to p-code functions are represented as 16-bit bytecode entry
offsets.  The backend emits `addr_func` when a C function name is used as a
value, and `CALL1` lowers to `icall`.

`ICALL_U8` expects the target function offset on top of the p-code stack, with
arguments below it in the same source-order convention as direct calls:

```text
... arg0 arg1 ... argN target
```

The interpreter pops `target`, creates a normal p-code call frame, then moves
the arguments into that frame exactly like `CALL_U16`.  The return value is
pushed back onto the p-code stack.  Host `pcinterp` validates that the target is
inside the bytecode image; the microcpu interpreter keeps the compact path and
assumes compiler-generated p-code is well-formed.

Native function pointers are not implemented yet.  External function
declarations still call through `NCALL` and the native table.

## Multi-module p-code

The current object format exposes one `__pcode_start`/`__pcd_global` pair per
p-code object, so the multi-module path merges textual `.pca` modules into one
p-code object for the program or tool being linked.  The merger:

- preserves public p-code function and data labels,
- rewrites external `ncall` instructions to `call` when the target function is
  defined by another p-code module in the same merged image,
- resolves `extern` p-code globals against data labels from other modules,
- rewrites internal compiler labels such as `L123`,
- rewrites `static_func` and `static_data_label` definitions to per-module
  private names so static symbols do not collide.

`test-pcode-multi` covers p-code-to-p-code cross-module calls, extern globals,
static isolation, and cross-module function pointers.  Cross-module native
function pointers remain unsupported; native calls still use `NCALL`.

## Native calls

`NCALL` looks up a native-table entry.  The p-code stack holds arguments in
source order before the call.  The interpreter pops the last argument first,
reconstructs the ordinary argument order, calls the native helper, and pushes
the 16-bit return value.

The host interpreter currently implements enough native calls for the first
p-code tests:

- `_strlen`
- `_putchar`
- `_puts`
- `_getchar`
- `_strcmp`
- `_strcpy`

The target microcpu interpreter uses the same bytecode semantics.  The p-code
object emits a native table with relocations to linked object symbols such as
runtime libc helpers or optional user native objects.  The current microcpu
interpreter implements `NCALL_U8`; `NCALL_U16` is reserved for a later larger
native table.

Optional native objects are linked between the runtime and the p-code object:

```text
pcode_interpreter.o
runtime_object.o
optional_native_objects.o...
pcode.o
```

Normal external C declarations in p-code are emitted as `NCALL` entries when
the function body is not present in the p-code module.  `microlink` resolves
those native table entries against runtime helpers or user-provided native
objects.  Native functions use the ordinary microcpu Small-C ABI; their `v0`
return value is pushed back onto the p-code stack.  The interpreter saves its
IP, operand stack pointer, and frame pointer around each native call.

## Microcpu interpreter

`runtime/pcode_interpreter.asm` is a compact assembly interpreter for the
microcpu target.  The simple p-code test link order is:

```text
pcode_interpreter.o
runtime_object.o        ; only when native calls are present
pcode.o
```

The p-code object exports `__pcode_entry`, `__pcode_start`, and
`__pcode_end`.  Because the current object format limits symbol names, the
target data/native-table labels use short aliases:

```text
__pcd_native    native address table
__pcd_ncount    native entry count
__pcd_global    p-code global/string data
__pcd_gend      end of p-code data
```

`ADDR_GLOBAL_U16`, `LGLOBAL_U16`, and `SGLOBAL_U16` operands are linked
absolute target addresses in the microcpu object path.  Internal p-code data
labels and external native globals both use ordinary object relocations, so
p-code can pass pointers to native code and can read native globals declared
with `extern`.

Interpreter state:

- p-code IP lives in a native register while executing.
- operand stack is a fixed 512-byte area of 16-bit cells.
- call depth is 16 frames.
- each p-code frame has a fixed 64-byte local/temporary area.
- native `sp` remains available for interpreter helper calls and `NCALL`.

When the top-level p-code function returns, the interpreter leaves the result
in native `v0` and branches to `__test_halt`, so `microemu
--stop-on-self-branch` can verify the final register value.

The microcpu interpreter currently covers the opcodes emitted by
`pcode-tests/001..044`: constants, local/global loads and stores, local/global
addressing, p-code direct calls including compact `CALL0/1/2_U16`, conditional
branches, arithmetic/logical comparisons, byte/word memory operations,
`DROP`/`DUP`/`SWAP`, `RET`, `NCALL_U8`, and `ICALL_U8`.  `switch` is lowered by
the p-code backend into an explicit compare-and-branch chain, not a dedicated
VM opcode.

Opcodes defined in the bytecode table but not yet exercised by the target test
suite remain implementation candidates for later coverage expansion.  The
backend still fails explicitly if it encounters an internal pseudo-code opcode
that has not been translated to the external stack VM.

`make -C smallc-microcpu test-pcode-native` validates native object calls with:

- a native arithmetic function,
- a native function that writes a native global read back by p-code,
- a native function returning a pointer to native string data,
- p-code string data passed into a native function.

## Size report

`make -C smallc-microcpu test-pcode-host` writes
`build/pcode/size-report.txt`.  `make -C smallc-microcpu
test-pcode-microemu` writes `build/pcode-microemu/size-report.txt`.
`make -C smallc-microcpu test-pcode-native` writes
`build/pcode-native/size-report.txt`.  For each p-code test the reports record:

- raw bytecode bytes
- global data bytes
- native table bytes
- total p-code object data size
- linked interpreter size status
- native backend assembly/binary comparison

For self-host size measurement, use:

```sh
make -C smallc-microcpu selfhost-pcode-smoke
```

The report is written to `build/selfhost-pcode/size-report.txt` and includes:

- per-module p-code generation PASS/FAIL
- unsupported internal pseudo-code opcode, if any
- bytecode, global data, string/literal, and native-table bytes
- p-code function, native-call, indirect-call, native-table, and global counts
- p-code optimizer removed roundtrips and byte savings
- pcode.o size when the current p-code object path can assemble it
- equivalent native object size
- estimated `smallcpp` and `smallcc` p-code image sizes
- comparison with `selfhost-link-smoke` when its report is available

This target is a measurement smoke only.  It does not link or run a
p-code-hosted compiler image.

For link/size smoke, use:

```sh
make -C smallc-microcpu selfhost-pcode-link-smoke
```

This target first refreshes `selfhost-pcode-smoke`, then attempts separate
links for `smallcpp` and `smallcc`.  Each tool's `.pca` modules are merged into
one p-code object and linked as:

```text
pcode_interpreter.o
generated hosted_stubs.o
<tool>.pcode.o
```

The generated hosted stubs provide dummy functions and dummy `stdin`/`stdout`/
`stderr` globals only to measure link size and unresolved symbols.  They are
not real file I/O and the linked images are not expected to run as compilers
yet.  The report is written to `build/selfhost-pcode-link/report.txt`; it
includes detailed p-code size diagnostics and classifies failures as missing
p-code modules, unresolved symbols, size overflow, symbol collision, relocation
limitation, linker failure, or other.

For execution smoke, use:

```sh
make -C smallc-microcpu selfhost-pcode-exec-smoke
```

This target first refreshes the p-code link smoke, then relinks each split tool
with `runtime/hosted_io.asm` instead of the generated link-only stubs:

```text
pcode_interpreter.o
hosted_io.o
<tool>.pcode.o
```

`hosted_io.o` is a minimal native hosted-service layer, not a libc.  It maps
`stdin`, `stdout`, and `stderr` to UART, treats UART RX byte `0x04` as EOF,
implements simple UART `fgetc`/`fgets`/`fputc`/`fputs`, ASCII ctype helpers,
small string helpers, and a bump `calloc` that starts after `__pcd_gend`.
`fopen` still returns 0 because no filesystem model exists yet.  `calloc`
halts with `V0=0xca10` if allocation would pass the hosted heap limit or wrap
the 16-bit address space.

The current execution smoke is report-only and intentionally honest: both
split tools start, print the Small-C banner through UART, and then hit
`V0=0xca10` before processing the tiny input.  This means the immediate blocker
has moved from bytecode/link size to runtime RAM footprint and data layout.

# Self-hosting status

This port is not self-hosting yet.  The current smoke check is deliberately
narrow: it feeds the canonical split compiler implementation modules to the
current smallc-microcpu compiler and records whether readable microasm can be
produced.  It does not run the compiler on microcpu.

## Running the smoke check

```sh
make -C smallc-microcpu selfhost-smoke
```

Outputs are written to:

```text
smallc-microcpu/build/selfhost-smoke/
```

For each attempted source file the target writes:

- `<name>.asm`: generated assembly, if any was emitted before the first
  blocker
- `<name>.o` and `<name>.obj.log`: object output and assembler log when
  `OBJECT_MODE=1` is used and the source compiles far enough
- `<name>.log`: full compiler stdout/stderr
- `report.txt`: PASS/FAIL summary with the first detected blocker and a
  suggested next feature.  The report also records symbol/macro/include usage,
  included compatibility headers, repeated include observations, and an
  approximate declaration contributor list.

The default target is report-only and exits successfully even when source files
fail compatibility checks.  To make failures fail the make target:

```sh
make -C smallc-microcpu selfhost-smoke STRICT=1
```

Each attempted compiler source has a timeout so parser non-progress is reported
instead of hanging the smoke target.  Override it with:

```sh
make -C smallc-microcpu selfhost-smoke SELFHOST_TIMEOUT=10
```

To also assemble successful smoke outputs to microasm object files:

```sh
make -C smallc-microcpu selfhost-smoke OBJECT_MODE=1
```

After all object smoke inputs compile, a report-only link experiment is
available:

```sh
make -C smallc-microcpu selfhost-link-smoke
```

This target first runs `selfhost-smoke OBJECT_MODE=1`, then attempts separate
links for the split tools, `smallcpp` and `smallcc`.  It writes
`build/selfhost-smoke/link-report.txt`.  The target exits 0 by default even
when linking fails; use `STRICT=1` to make a link failure fail the make target.

## Current inputs

The smoke check attempts the same canonical modules used by the host build.
There is no selfhost-only wrapper layout and no active monolithic `cc1.c`
compiler path.

`smallcpp` modules:

- `src/smallcpp_main.c`
- `src/smallcpp_macro.c`
- `src/smallcpp_io.c`
- `src/shared_lex.c`
- `src/shared_host_compat.c`

`smallcc` modules:

- `src/smallcc_main.c`
- `src/smallcc_driver.c`
- `src/smallcc_input.c`
- `src/smallcc_types.c`
- `src/smallcc_decl.c`
- `src/smallcc_func.c`
- `src/smallcc_stmt.c`
- `src/smallcc_lex.c`
- `src/smallcc_expr.c`
- `src/smallcc_emit.c`
- `src/smallcc_codegen_microcpu.c`
- `src/smallcc_codegen_pcode.c`
- `src/shared_host_compat.c`

The split is the canonical source layout for host, object, and selfhost smoke
builds.  If a module is split for target object size, the host build uses that
split module too.

## Current result snapshot

The original `#include <stdio.h>` open failure is addressed by controlled
compatibility headers under `smallc-microcpu/include/`; the smoke target passes
`-I include` and does not search host system include directories.  The smoke
target also defines `SMALLC_SELFHOST` with `-D` so host-only prototype imports
are hidden from the target-compatibility pass.

The previous function-like macro blocker, for example:

```c
#define abort(code) exit((int)(code))
```

is now handled by the simple macro expander.  The former global symbol table
overflow around `intptr_t chrcon();` was not a real capacity limit; it came
from importing the host-only `smallc_proto.h` declaration list into selfhost
smoke inputs.  `SMALLC_SELFHOST` now suppresses that include.  Repeated
compatible function prototypes are treated as declarations, multiline
prototypes are skipped correctly, and a prototype followed by the actual
function definition no longer reports `already defined`.

The current report advances beyond the old symbol/prototype blockers.  The
compiler now keeps 31 significant identifier characters, so names such as
`typedef_count`, `typedef_type`, `macro_argc`, and `macro_argfirst` no longer
collide.  Minimal `void` functions, file-scope `static` functions/globals, and
multiline ANSI function definitions are also accepted.

The newer blockers from the previous phases are also addressed:

- pointer depth greater than one, including `char **`
- typedef names in K&R-style argument declarations
- local declarations using typedef names such as `size_t`
- ignored `const` qualifiers without relying on the host-only `const` macro
- `void *` as a pointer-sized compatibility type
- C-style casts used by the host compatibility layer
- `sizeof(*p)` on pointer expressions
- unsigned integer suffixes such as `1u`
- multiline global declarations and multiline initializer lists
- minimal indirect calls through function-pointer arguments
- the literal pool capacity needed by `smallcc_codegen_microcpu.c`

Without `OBJECT_MODE=1`, all canonical compiler modules currently compile to
generated microasm.

With `OBJECT_MODE=1`, all canonical compiler modules assemble to object files.
The former combined-frontend single-object 64K blocker is resolved by making
the split modules canonical instead of maintaining a monolithic host path.

The split also exposed a separate object-assembler branch-range limit in
large generated functions.  Object-mode backend output now uses the existing
microasm `jmp` macro for compiler-generated jumps, so branch targets are not
limited by the short relative `b` range.  Normal binary-mode output keeps the
short `b` form.

The link smoke evaluates two separate tool images rather than the old combined
compiler.  Current report-only status:

- `smallcpp`: object compilation passes; link fails on unresolved target-hosted
  `_stderr` support.  Estimated text/data are about 30310/31319 bytes.
- `smallcc`: object compilation passes; link still exceeds the current linker
  output buffer.  With the experimental p-code backend module included in the
  canonical build, estimated text/data are about 90800/27543 bytes, so further
  split/reduction or a larger target layout is still needed.

A link failure here is still report-only by default; full target execution
remains future work.

An experimental p-code backend now exists as a size-reduction path.  It lowers
the existing internal register-oriented pseudo-code into an external 8-bit
stack-VM bytecode and has both host and microcpu interpreter coverage for a
broader subset.  `test-pcode-host` and `test-pcode-microemu` currently pass
`pcode-tests/001..041`, including comparisons, short-circuit logical
operators, bitwise/shift operations, local/global arrays, basic pointers,
string indexing, enum/typedef basics, simple struct access, `switch`, static
and void functions, pointer-to-pointer loads, casts, pre/post increment and
decrement, p-code function-pointer indirect calls, and native calls to
`_strlen`, `_strcpy`, and `_putchar` through relocatable target native-call
operands.
`test-pcode-native` also passes and validates calls from p-code into
separately compiled native object files, including native globals, native
pointer returns, and p-code string pointers passed to native code.  This does
not replace the native backend and is not full self-hosting yet.

The target-side p-code size report is written to
`build/pcode-microemu/size-report.txt`.  In the current small tests the
microcpu interpreter object is about 4.6 KB, pure p-code linked images are
about 3.8-3.9 KB, and native-call tests link in `runtime_object.o` for a total
around 4.5 KB.  Native object call sizes are reported in
`build/pcode-native/size-report.txt`.

The self-host p-code size smoke is:

```sh
make -C smallc-microcpu selfhost-pcode-smoke
```

It writes `build/selfhost-pcode/size-report.txt` and does not link or run a
p-code-hosted compiler.  Current report-only measurements show:

- `smallcpp`: all modules generate p-code.  Estimated p-code image is about
  48.1 KB versus 87.1 KB summed native object size, roughly 39.0 KB smaller.
- `smallcc`: all modules now generate p-code.  Estimated p-code image is about
  65.5 KB versus 187.3 KB summed native object size, roughly 121.8 KB smaller.
  The p-code optimizer removes about 6.1K temp store/load roundtrips from
  `smallcc`, rewrites a small number of live non-short local temp roundtrips,
  compacts local branch patterns, and saves about 12.5 KB of bytecode before
  link-time object layout.
  The previous `CALL1` blocker in `smallcc_expr.c` is resolved by `ICALL_U8`
  support for p-code function pointers.

The size smoke also reports remaining peephole candidates after the current
optimizer.  Most remaining same-temp store/load pairs are short local-temp
accesses where `dup; slocal` is not smaller than the original pair.  They
identify where a future basic-block or stack-effect optimizer should focus;
remaining branch-to-branch counts show places where threading would require a
larger encoded branch or a more global rewrite.

The p-code link smoke is:

```sh
make -C smallc-microcpu selfhost-pcode-link-smoke
```

It writes `build/selfhost-pcode-link/report.txt` and remains report-only unless
`STRICT=1` is set.  It now assembles each `.pca` module to a separate
relocatable p-code object and links those objects directly with the p-code
interpreter plus generated link-only hosted stubs.  The `.pca` merger remains
only as a debug/compatibility tool.  Current status:

- `smallcpp`: direct p-code object link smoke passes.  The linked image is
  about 45.8 KB with `PCODE_OPT=1`, using dummy hosted stubs for file I/O and
  standard streams.
- `smallcc`: direct p-code object link smoke passes with `PCODE_OPT=1`.  The
  p-code payload is linked as multiple p-code objects; the final smoke image is
  about 62.5 KB, below the 64K binary limit.

This suggests p-code is a promising size path, but the remaining work is not
just bytecode density.  The next blockers are native function-pointer
semantics if needed, target-hosted file I/O/argv support, and final image
layout.  There is not much size margin left for real hosted I/O, so further
splitting or data-layout work may still be needed.

The p-code execution smoke is:

```sh
make -C smallc-microcpu selfhost-pcode-exec-smoke
```

It writes `build/selfhost-pcode-exec/report.txt` and
`build/selfhost-pcode-exec/memory-map.txt`, and remains report-only unless
`STRICT=1` is set.  The target relinks each split image from the same direct
p-code object set used by link smoke, but with `runtime/hosted_io.asm`, a tiny
native hosted layer that maps standard streams to UART and treats UART RX byte
`0x04` as EOF.  It does not provide a real filesystem; `fopen` still returns 0.
The memory map includes linked object ranges, p-code bytecode/data ranges,
largest exported writable p-code globals, VM/native stack ranges, hosted heap
diagnostics, and overlap checks.

Current execution status:

- `smallcpp`: links and starts on `hc1200-cpu`; it prints the banner through
  UART, then halts with `V0=0xca10`.  The current direct-linked image is 46,703
  bytes.  The hosted diagnostic identifies the failed allocation as the
  13,000-byte compiler symbol table (`symtab`), requested after earlier
  `smallcpp` table allocations left only 332 bytes below the hosted heap guard.
- `smallcc`: links and starts on `hc1200-cpu`; it prints the banner through
  UART, then halts with `V0=0xca10`.  The current direct-linked image is 63,409
  bytes.  The hosted diagnostic identifies the failed allocation as the
  1,600-byte staging buffer (`stage`), with 862 bytes left below the hosted
  heap guard.

`V0=0xca10` is the hosted runtime's explicit heap-exhaustion marker.  The
minimal bump allocator starts after `__pcd_gend` and refuses allocations that
would pass the `0xfde0` MMIO guard or wrap the 16-bit address space.  The next
selfhost blocker is therefore not missing bytecode lowering or basic hosted
I/O, but the runtime RAM footprint of the compiler tables and generated p-code
globals.  Solving that requires smaller/lazier tables, moving unneeded static
tables out of each split image, a different data layout, or an explicitly
larger hosted memory model.

The global symbol table was raised from 200 to 300 entries only after the
self-host report showed real compiler frontend pressure with include guards
working, zero repeated includes, and the controlled headers already minimized.

## Known blockers

The most likely next blockers are:

- target-hosted file I/O, diagnostics, and command-line runtime support
- runtime heap/table footprint for running `smallcpp` and `smallcc` inside a
  16-bit address space
- preserving enough p-code `smallcc` size margin for real hosted I/O
- link-time layout for larger compiler data
- full `#if` expressions and richer conditional preprocessing
- large switch tables
- complex initializers and struct initializers
- anonymous structs and anonymous typedef structs
- `union`
- full function pointer semantics beyond p-code-to-p-code indirect calls
- command-line `argc`/`argv` and environment handling on the target
- target file I/O for compiler input and output

Optional host preprocessing with `cc -E -P` may be useful later, but it can also
introduce constructs outside the current Small-C subset.  It should remain an
explicit self-hosting experiment rather than part of the normal test suite.

The compatibility headers in `include/` are intentionally tiny.  They provide
only declarations and constants needed to parse current smoke inputs; they do
not implement target file I/O or a hosted libc.

## Compiler-source coding rules

Compiler implementation changes should continue to stay close to old Small-C
style so the code moves toward eventual self-hosting:

- keep declarations at the beginning of functions
- avoid C99/C11 syntax
- avoid `stdint.h`, `stdbool.h`, `inline`, and `restrict`
- avoid `//` comments
- avoid mixed declarations and statements
- avoid heap allocation unless the original compiler already uses it
- prefer fixed-size tables, integer indexes, and simple arrays
- do not depend on newly-added language features inside the compiler
  implementation until those features are stable and documented

## Future plan

The next self-hosting steps should be incremental:

1. Decide how a full compiler image should fit into the target memory model,
   or define an overlay/banked/tool-hosted strategy explicitly.
2. Add or stub the target runtime pieces needed for compiler diagnostics and
   host-style I/O.
3. Link multiple generated compiler units with a target-appropriate runtime.
4. Add enough target runtime for compiler input, output, diagnostics, and
   command-line handling.

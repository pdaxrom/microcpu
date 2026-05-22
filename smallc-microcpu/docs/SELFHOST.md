# Self-hosting status

This port is not self-hosting yet.  The current smoke check is deliberately
narrow: it feeds selected compiler implementation source files to the current
smallc-microcpu compiler and records whether readable microasm can be produced.
It does not link or run the compiler on microcpu.

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

## Current inputs

The smoke check currently attempts the real compiler implementation files:

- `src/cc1.c`
- `src/cc2.c`
- `src/cc3.c`
- `src/cc4.c`
- `src/codegen_microcpu.c`
- `src/host_compat.c`

These are host-buildable C sources, not yet target-ready translation units.
Early failures are expected while the frontend lacks the preprocessing and
multi-file support needed for the compiler source itself.

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
- the literal pool capacity needed by `codegen_microcpu.c`

Without `OBJECT_MODE=1`, all selected compiler source files currently compile
to generated microasm:

- `cc1.c`: PASS to `.asm`
- `cc2.c`: PASS to `.asm`
- `cc3.c`: PASS to `.asm`
- `cc4.c`: PASS to `.asm`
- `codegen_microcpu.c`: PASS to `.asm`
- `host_compat.c`: PASS to `.asm`

With `OBJECT_MODE=1`, five of the six selected files now assemble to object
files:

- `cc1.c`: FAIL after generating a large `.asm`; object assembly appears to
  hit the current single-object 64K code-size limit.
- `cc2.c`: PASS to `.o`
- `cc3.c`: PASS to `.o`
- `cc4.c`: PASS to `.o`
- `codegen_microcpu.c`: PASS to `.o`
- `host_compat.c`: PASS to `.o`

The global symbol table was raised from 200 to 300 entries only after the
self-host report showed that `cc1.c` was legitimately using about 253 global
symbols with include guards working, zero repeated includes, and the controlled
headers already minimized.

## Known blockers

The most likely next blockers are:

- splitting or otherwise shrinking `cc1.c` enough for single-object assembly,
  or extending the object format/toolchain to represent larger modules
- full compiler linking and cross-unit runtime layout
- link-time layout for larger compiler data
- full `#if` expressions and richer conditional preprocessing
- large switch tables
- complex initializers and struct initializers
- anonymous structs and anonymous typedef structs
- `union`
- full function pointer semantics beyond simple indirect calls
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

1. Split or shrink `cc1.c`, or extend object handling for modules whose
   generated code exceeds 64K.
2. Add a non-default link-only selfhost smoke once all objects can be emitted.
3. Link multiple generated compiler units with runtime objects.
4. Add enough target runtime for compiler input, output, diagnostics, and
   command-line handling.

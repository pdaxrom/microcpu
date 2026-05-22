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

After all object smoke inputs compile, a report-only link experiment is
available:

```sh
make -C smallc-microcpu selfhost-link-smoke
```

This target first runs `selfhost-smoke OBJECT_MODE=1`, then links the emitted
compiler objects with the current runtime objects.  It writes
`build/selfhost-smoke/link-report.txt`.  The target exits 0 by default even
when linking fails; use `STRICT=1` to make a link failure fail the make target.

## Current inputs

The smoke check currently attempts the real compiler implementation files:

- `src/cc1.c`
- `src/cc2.c`
- `src/cc3.c`
- `src/cc4.c`
- `src/codegen_microcpu.c`
- `src/host_compat.c`

For `OBJECT_MODE=1`, `src/cc1.c` is split into wrapper translation units:

- `src/cc1_main.c`
- `src/cc1_types.c`
- `src/cc1_decl.c`
- `src/cc1_preproc.c`
- `src/cc1_func.c`
- `src/cc1_stmt.c`
- `src/cc1_io.c`

Each wrapper defines one `CC1_*` section macro and includes the original
`cc1.c`.  Normal host builds and non-object selfhost smoke still use `cc1.c`
directly.  The split is intentionally mechanical: it avoids a single oversized
object without rewriting the compiler frontend.

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

With `OBJECT_MODE=1`, all selected compiler modules now assemble to object
files.  The former `cc1.c` single-object 64K blocker is resolved by the split
wrapper modules:

- `cc1_main.c`: PASS to `.o`
- `cc1_types.c`: PASS to `.o`
- `cc1_decl.c`: PASS to `.o`
- `cc1_preproc.c`: PASS to `.o`
- `cc1_func.c`: PASS to `.o`
- `cc1_stmt.c`: PASS to `.o`
- `cc1_io.c`: PASS to `.o`
- `cc2.c`: PASS to `.o`
- `cc3.c`: PASS to `.o`
- `cc4.c`: PASS to `.o`
- `codegen_microcpu.c`: PASS to `.o`
- `host_compat.c`: PASS to `.o`

The split also exposed a separate object-assembler branch-range limit in
large generated functions.  Object-mode backend output now uses the existing
microasm `jmp` macro for compiler-generated jumps, so branch targets are not
limited by the short relative `b` range.  Normal binary-mode output keeps the
short `b` form.

The link smoke currently fails after object compilation with:

```text
Output buffer overflow
```

That means object compilation coverage has advanced past the `cc1.c` blocker,
but the full compiler image/link layout is still future work.  This is not a
request to increase a limit blindly; the linked compiler image and target
runtime/hosting plan need to be designed before the compiler can run on the
target.

The global symbol table was raised from 200 to 300 entries only after the
self-host report showed that `cc1.c` was legitimately using about 253 global
symbols with include guards working, zero repeated includes, and the controlled
headers already minimized.

## Known blockers

The most likely next blockers are:

- final linked compiler image size and linker output layout
- full compiler linking and target runtime layout
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

1. Decide how a full compiler image should fit into the target memory model,
   or define an overlay/banked/tool-hosted strategy explicitly.
2. Add or stub the target runtime pieces needed for compiler diagnostics and
   host-style I/O.
3. Link multiple generated compiler units with a target-appropriate runtime.
4. Add enough target runtime for compiler input, output, diagnostics, and
   command-line handling.

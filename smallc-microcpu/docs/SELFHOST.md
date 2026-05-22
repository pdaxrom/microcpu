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

The newer blockers from the previous phase are also addressed:

- pointer depth greater than one, including `char **`
- typedef names in K&R-style argument declarations
- ignored `const` qualifiers
- the literal pool capacity needed by `codegen_microcpu.c`

With `OBJECT_MODE=1`, `cc2.c` and `codegen_microcpu.c` currently compile to
microasm and assemble to object files.  The other source files now fail later:

- `cc1.c`: currently stops near a comma-separated K&R argument declaration
  form (`nogo, ...`) that the smoke parser still does not understand.
- `cc3.c`: stops at `sizeof(*is)`, which needs `sizeof` on dereferenced
  pointer expressions.
- `cc4.c`: stops near a comma-oriented declaration/initializer form in the
  backend tables.
- `host_compat.c`: stops at `size_t limit;`, so local declarations using
  typedef names still need to be supported.

## Known blockers

The most likely next blockers are:

- full `#if` expressions and richer conditional preprocessing
- local declarations using typedef names
- comma-separated K&R argument declarations
- `sizeof` on dereferenced pointer expressions
- full compiler linking and cross-unit runtime layout
- link-time layout for larger compiler data
- large switch tables
- complex initializers and struct initializers
- anonymous structs and anonymous typedef structs
- `union`
- function pointers
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

1. Add local declarations using typedef names, including `size_t`.
2. Add the remaining old-style declaration forms used by `cc1.c` and `cc4.c`.
3. Extend `sizeof` handling for pointer dereference expressions.
4. Compile individual translation units to objects consistently.
5. Link multiple generated compiler units with runtime objects.
6. Add enough target runtime for compiler input, output, diagnostics, and
   command-line handling.

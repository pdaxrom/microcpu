# Self-hosting status

This port is not self-hosting yet.  The current smoke check is deliberately
narrow: it feeds selected compiler implementation source files to the current
smallc-microcpu compiler and records whether readable microasm can be produced.
It does not assemble, link, or run the compiler on microcpu.

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
- `<name>.log`: full compiler stdout/stderr
- `report.txt`: PASS/FAIL summary with the first detected blocker and a
  suggested next feature

The default target is report-only and exits successfully even when source files
fail compatibility checks.  To make failures fail the make target:

```sh
make -C smallc-microcpu selfhost-smoke STRICT=1
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

No real compiler implementation file is expected to pass yet.  The original
`#include <stdio.h>` open failure is addressed by controlled compatibility
headers under `smallc-microcpu/include/`; the smoke target passes `-I include`
and does not search host system include directories.

The current first blocker for all attempted real compiler files is now the
function-like macro in `src/host_compat.h`:

```c
#define abort(code) exit((int)(code))
```

The smoke report records that as `unsupported function-like macro`.  This is
useful signal: include path handling is no longer the first blocker; the next
self-hosting work is either avoiding host-only function-like macros in target
headers or adding a very small function-like macro subset.

## Known blockers

The most likely next blockers are:

- function-like macros in host compatibility headers
- full `#if` expressions and richer conditional preprocessing
- `static` declarations and static functions
- `extern` declarations
- multiple translation units and cross-unit symbol resolution
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

1. Remove or shim host-only function-like macros for the self-host subset.
2. Teach the frontend only the smallest missing declaration/preprocessor
   features required by the compiler sources.
3. Compile individual translation units to assembly consistently.
4. Add an assembler/linker flow for multiple generated units.
5. Add enough target runtime for compiler input, output, diagnostics, and
   command-line handling.

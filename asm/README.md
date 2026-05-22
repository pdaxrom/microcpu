Documentation

Full assembler and ISA reference (including RTL semantics): docs/isa.md

Usage

Build the assembler:

```
make -C asm
```

Run it:

```
asm/microasm [-verilog|-binary|-object] [-D name[=expr]|--define name[=expr]] [-U name|--undef name] <input.asm> [output]
asm/microasm [-verilog|-binary|-obj] [-Dname[=expr]|--define=name[=expr]] [-Uname|--undef=name] <input.asm> [output]
```

- default output is a `.mem` hex file.
- `-binary` writes raw bytes.
- `-verilog` writes a Verilog SRAM initialization module.
- `-object` / `-obj` writes a UniCROSS-style object file for `microlink`.
- `-D` / `--define` creates a global constant before pass 1. If `=expr` is
  omitted, the value is `1`.
- `-U` / `--undef` removes a command-line define before pass 1.

Examples:

```
asm/microasm -D DEBUG -D ROM_BASE='$8000' examples/monitor.asm monitor.mem
asm/microasm --define=FEATURE_UART=1 --undef DEBUG examples/monitor.asm
```

Object files and linking

`microasm -object` supports these object-related directives:

```
EXTERN <symbol>[, <symbol>...]
PUBLIC <symbol>[, <symbol>...]
ENTRY <expr>
```

- `EXTERN` declares symbols resolved by `microlink` from other object files.
- `PUBLIC` exports labels or constants from the current object file.
- `ENTRY <expr>` stores an object entry point. If omitted, the object header
  entry point is `$FFFF` (none).
- `GLOBAL` remains a procedure-local directive; use `PUBLIC` for object exports.

Link object files into a final image:

```
asm/microlink [-verilog|-binary] [-symbols] [-org address] [-o output] <input.obj>...
```

`microlink` writes the same final output formats as `microasm`: `.mem` by
default, raw binary with `-binary`, or Verilog SRAM initialization with
`-verilog`. Use `-symbols` or `--symbols` to print the resolved public symbol
table to stdout. It does not generate relocatable output files.

Disassembly

Disassemble raw binary or object files:

```
asm/microdis [-binary|-object] [-org address] <input.bin|input.obj>
```

Input mode is auto-detected by default. Use `-binary` or `-object` / `-obj` to
force a mode. `-org` controls the base address printed in the listing. Object
disassembly includes `extern`/`public` declarations, public labels, entry point
information, and relocation comments. `microdis` does not infer data regions;
it decodes every two-byte word as an instruction and emits an odd trailing byte
as `db`.

Conditional assembly

The assembler supports pass-1 conditional assembly:

```
IF <expr>
IFDEF <symbol>
IFNDEF <symbol>
ELSE
ENDIF
```

Skipped lines are not parsed as labels, directives, macros, or instructions.
`IF <expr>` must be resolvable in pass 1. `IFDEF` and `IFNDEF` test symbols
already seen by pass 1, including command-line `-D` defines. Conditional blocks
may be nested up to 32 levels.

Include files

- include/pseudo.inc: common pseudo-instruction macros.
- include/devmap.inc: board/device address constants.
- include/int32.inc: 32-bit arithmetic procedures. It emits code, so include it
  after the calling code or branch around it. Values use v1:v0 as lhs/result
  and v3:v2 as rhs.
- include/fis.inc / include/fis16.inc: FIS16 floating point procedures
  (`fadd`, `fsub`, `fmul`, `fdiv`). It emits code and includes int32.inc
  internally. Routines use stack frames for scratch state and are reentrant.
- include/fis32.inc: 32-bit FIS-like floating point procedures (`f32add`,
  `f32sub`, `f32mul`, `f32div`) using sign + excess-0200 exponent + 23-bit
  fraction. It emits code, includes int32.inc internally, and is reentrant.

Testing

Run assembler smoke tests:

sh scripts/test-asm-smoke.sh

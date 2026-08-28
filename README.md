(c) sashz <sashz@pdaXrom.org>, 2020-2021

[GitHub project page](https://github.com/pdaxrom/microcpu)

# MICROCPU - 16-bit RISC CPU (Version 2)

This is the **legacy/original RISC CPU** documentation: [rtl/cpu.v](rtl/cpu.v),
native assembly programs and the UART bootloader. `microasm` defaults to
`--cpu original`. The two derived microengines have their own documentation:

| Version | CPU documentation | HC1200 microcomp hardware |
|---|---|---|
| `original` (legacy, main reference) | This README | [Original RISC microcomp](docs/hc1200-microcomp.md) |
| `j11` (preserved microengine) | [J-11 reference engine](docs/fpga-j11.md) | [Reference J-11 microcomp](docs/hc1200-microcomp-j11.md) |
| `ucode` (specialized microengine) | [Specialized engine](docs/ucode-cpu.md) | [Specialized microcomp; stable J11 / RT-11 SD boot](docs/hc1200-microcomp-ucode.md) |

Shared guides: [CPU-profile comparison](docs/cpu-profiles.md),
[Diamond build/programming](docs/diamond.md),
[Icarus and Verilator simulations](testbench/README.md).
These are native CPU profiles; guest PDP-11 tests use the separate
`microasm11 --cpu dcj-11` assembler.

Legacy quick start, from the repository root:

```sh
make -C asm
asm/microasm --list-cpus
make -C testbench run-smoke_pass   # Icarus; original CPU only

# Ubuntu / Diamond 3.14: generate the original board's SRAM.
make -C boards/hc1200-microcomp original \
  DIAMOND_HOME=/home/sash/.local/lscc/diamond/3.14
```

For legacy hardware open **`microcomp-original.ldf`**. The current
`microcomp.ldf` and the board Makefile's default target still select the
specialized SD-boot system; documenting legacy first does not change those
build defaults. Plain `make` includes legacy SCUBA generation and needs
Diamond; plain `make test` includes original and preserved `j11` tests, but
not the specialized `ucode`/SD suites.

* [Registers](#registers)
* [Address modes](#address-modes)
* [Instructions](#instructions)
  * [Data Movement Instructions](#data-movement-instructions)
  * [Arithmetic and Logic Instructions](#arithmetic-and-logic-instructions)
  * [Control Flow Instructions](#control-flow-instructions)
  * [CPU Modes Control](#cpu-modes-control)
  * [Interrupts](#interrupts)
* [MicroAssembler](#microassembler)
  * [Assembler directives](#assembler-directives)
  * [Conditional assembly](#conditional-assembly)
  * [Assembler macro definition](#assembler-macro-definition)
  * [Assembler procedures](#assembler-procedures)
  * [Command line options](#command-line-options)
  * [Object files and linker](#object-files-and-linker)
  * [Disassembler](#disassembler)
* [Bootloader](#bootloader)
  * [Bootloader options](#bootloader-options)
* [Lattice Diamond programmer and ftdi jtag dual channel board](#lattice-diamond-programmer-and-ftdi-jtag-dual-channel-board)
* [Microcontroller with Lattice MachXO2-1200 microboard](docs/hc1200-mcu.md)
* [Microcomputer with Lattice MachXO2-1200](docs/hc1200-microcomp.md)
* [FPGA J-11 microengine](docs/fpga-j11.md)

## Registers

The processor has eight 16-bit registers. The register 0 (PC) using as program counter.

Numeric | Name |Alias
-------|----|-----
0|R0|PC
1|R1|SP
2|R2|LR
3|R3|V0
4|R4|V1
5|R5|V2
6|R6|V3
7|R7|V4

Each register has high byte and low byte:

15 14 13 12 11 10 09 08 | 07 06 05 04 03 02 01 00
:-:|:-:
HIGH BYTE|LOW BYTE

[Top](#microcpu---16-bit-risc-cpu-version-2)

## Address modes

The processor has 5 addressing modes that can be used by the programmer:

1. Register
2. Immediate
3. Immediate indexed
4. Register indexed
5. Relative

[Top](#microcpu---16-bit-risc-cpu-version-2)

## Instructions

Machine instructions generally fall into three categories: data movement, arithmetic/logic, control-flow and cpu modes control.
We use the following notation:

Notation | Description
--------|-----------------------
`<dst>`|Any destination register
`<src>`|Any source register
`<imm>`|8-bit immediate
`<imm16>`|16-bit immediate
`<idx>`|Any register or 4-bit unsigned immediate
`<arg1>`|Any register
`<arg2>`|Any register or 4-bit unsigned immediate
`<rel>`|11-bit signed immediate

[Top](#microcpu---16-bit-risc-cpu-version-2)

### Data Movement Instructions

Instruction | | Description
------------|-|-----------
`LDRL <dst>, <src>, <idx>`|`RL<dst> = M[R<src> + idx]`|Load low byte from source address + index
`STRL <dst>, <src>, <idx>`|`M[R<src> + idx] = RL<dst>`|Store low byte to source address + index
`LDR  <dst>, <src>, <idx>`|`R<dst> = M[R<src> + idx]`|Load register (2 bytes) from source address + index
`STR  <dst>, <src>, <idx>`|`M[R<src> + idx] = R<dst>`|Store register (2 bytes) to source address + index
`SETL <dst>, <imm>`|`RL<dst> = imm`|Copy low byte from constant
`SETH <dst>, <imm>`|`RH<dst> = imm`|Copy high byte from constant
`MOVL <dst>, <src>`|`RL<dst> = RL<src>`|Copy source low byte to destination low byte
`MOVH <dst>, <src>`|`RH<dst> = RL<src>`|Copy source low byte to destination high byte
`MOV  <dst>, <src>`|`R<dst> = R<src>`|Copy data from source to destination register

Little endian byte order using for LDR and STR.

Examples:
```
    SETL V0, 0
    SETH V0, $10
    LDRL V1, V0, 0
    SETL V2, 1
    SETH V2, 0
    STR  V1, V0, V2
    MOV V3, V2
```

[Top](#microcpu---16-bit-risc-cpu-version-2)

### Arithmetic and Logic Instructions

Instruction | | Description
------------|-|-----------
`ADD  <dst>, <arg1>, <arg2>`|`<dst> = <arg1> + <arg2>`|Add
`SUB  <dst>, <arg1>, <arg2>`|`<dst> = <arg1> - <arg2>`|Subtract
`SHL  <dst>, <arg1>, <arg2>`|`<dst> = <arg1> << <arg2>`|Logic shift left
`SHR  <dst>, <arg1>, <arg2>`|`<dst> = <arg1> >> <arg2>`|Logic shift right
`AND  <dst>, <arg1>, <arg2>`|`<dst> = <arg1> & <arg2>`|And
`OR   <dst>, <arg1>, <arg2>`|`<dst> = <arg1> \| <arg2>`|Or
`INV  <dst>, <arg1>`|`<dst> = ~<arg1>`|Inversion
`XOR  <dst>, <arg1>, <arg2>`|`<dst> = <arg1> ^ <arg2>`|Exclusive Or
`SXT  <dst>, <arg1>`|`<dst> = sign <arg1>`|Sign extend

Examples:
```
    ADD V0, V1, V2
    SUB V0, V2, V1
    SHR V0, V0, 1
    SXT V1, V1
```

[Top](#microcpu---16-bit-risc-cpu-version-2)

### Control Flow Instructions

Instruction | | Description
------------|-|-----------
`B   <rel>`|`PC = PC + <rel>`|Branch
`EQ  <arg1>,<arg2>`|`PC = PC + (<arg1> == <arg2>) ? 2 : 0` |Skip next command if arg1 and arg2 are equal
`NE  <arg1>,<arg2>`|`PC = PC + (<arg1> != <arg2>) ? 2 : 0` |Skip next command if arg1 and arg2 are not equal
`LT  <arg1>,<arg2>`|`PC = PC + (<arg1> <  <arg2>) ? 2 : 0` |Skip next command if arg1 is less than arg2 (signed)
`GE  <arg1>,<arg2>`|`PC = PC + (<arg1> >= <arg2>) ? 2 : 0` |Skip next command if arg1 is greater then arg2 or equal (signed)
`LTU <arg1>,<arg2>`|`PC = PC + (<arg1> <  <arg2>) ? 2 : 0` |Skip next command if arg1 is less than arg2 (unsigned)
`GEU <arg1>,<arg2>`|`PC = PC + (<arg1> >= <arg2>) ? 2 : 0` |Skip next command if arg1 is greater then arg2 or equal (unsigned)
`BTC <arg1>,<arg2>`|`PC = PC + (<arg1> &  <arg2>) ? 2 : 0` |Skip next command if arg1 AND arg2 result is zero
`BTS <arg1>,<arg2>`|`PC = PC + (<arg1> &  <arg2>) ? 2 : 0` |Skip next command if arg1 AND arg2 result is not zero

Examples:
```
    B	start
    EQ	V0, V1
    B	not_the_same
    B	the same
```

[Top](#microcpu---16-bit-risc-cpu-version-2)

### CPU Modes Control

Instruction | | Description
------------|-|------------
`SWS`|`UPC = PC; PC = VEC_SUPER`|Switch to superuser mode
`SWU`|`PC = UPC`|Return to user mode
`GETP <dst>`|`<dst> = <User PC>`|Get user program counter
`SETP <src>`|`<User PC> = <src>`|Set user program counter

Examples:
```
    ORG	$0
    B	start
    B	su
    ...
su  SUB SP, SP, 2
    PUSH V0
    GETP V0
    ...
    SETP V0
    POP  V0
    ADD SP, SP, 2
    SWU
    ...
ini SWS
    ...
```

[Top](#microcpu---16-bit-risc-cpu-version-2)

## Interrupts

The system supports two interrupts - the CPU command to switch to superuser mode (SWS command) and peripheral interrupt (external signal). Both interrupts cause a jump to address $0002 while saving the interrupted address in a special register, which is available for modification using the GETP and SETP commands. Exit from the interrupt mode is performed using the SWU command. Until the end of the execution of the mode, other interrupts are prohibited.

[Top](#microcpu---16-bit-risc-cpu-version-2)

## MicroAssembler

Assembler has support for macros, procedures, include files, constants, and
conditional assembly. Since the processor has a limited number of instructions,
some instructions can be implemented as macros.

[Top](#microcpu---16-bit-risc-cpu-version-2)

### Assembler directives

Directive | Description
----------|-----------
`<symbol> EQU <exp>`|Set a symbol equal to an expression
`DB <imm>[,<imm>...]`|Define constant byte(s)
`DW <imm16>[,<imm16>...]`|Define constant word(s)
`DS <imm16>[,<imm>]`|Reserves num bytes of space and initializes them to val (optional, default 0).
`ALIGN <imm>`|Align address to num bits
`ORG <imm16>`|Set location address counter
`INCLUDE <file name>`|Include external source file
`CHKSUM`|Insert constant word to binary to sum all words as $FFFF
`IF <exp>`|Assemble following lines if expression is non-zero
`IFDEF <symbol>`|Assemble following lines if symbol is already defined
`IFNDEF <symbol>`|Assemble following lines if symbol is not defined
`ELSE`|Switch to alternate conditional assembly branch
`ENDIF`|End conditional assembly block
`EXTERN <symbol>[,<symbol>...]`|Declare symbols resolved from another object module
`PUBLIC <symbol>[,<symbol>...]`|Export symbols from the current object module
`ENTRY <exp>`|Set object entry point
`CPU <profile>`|Assert the CLI-selected native profile (`original`, `j11` or `ucode`); does not switch ISA

Examples:
```
    INCLUDE functions.inc
CONST_ONE EQU 1
CONST_TWO EQU 2
    ORG $100
    DB 1, $2, $3, 4, 5
    DB "Hello, World", 0
    DB 'About'
    DW $1234, 8192, 0
    DS 32
    DS 64,$FF
    ALIGN 4
```

[Top](#microcpu---16-bit-risc-cpu-version-2)

### Conditional assembly

Conditional directives are evaluated in pass 1 and control which lines are
assembled in both passes. Skipped lines are not parsed as labels, directives,
macros, or instructions.

Directive | Description
---------|-----------
`IF <exp>`|True when expression evaluates to non-zero. The expression must be resolvable in pass 1.
`IFDEF <symbol>`|True when symbol was already seen by pass 1.
`IFNDEF <symbol>`|True when symbol was not already seen by pass 1.
`ELSE`|Selects the opposite branch of the current conditional block.
`ENDIF`|Closes the current conditional block.

Conditional blocks may be nested up to 32 levels.

Example:
```
FEATURE_UART EQU 1

IF FEATURE_UART
    INCLUDE uart.inc
ELSE
    DB "UART disabled", 0
ENDIF

IFDEF DEBUG
    DB "debug", 0
ENDIF
```

[Top](#microcpu---16-bit-risc-cpu-version-2)

### Assembler macro definition

Directive | Description
---------|-----------
`MACRO <name>`|Start macro
`ENDM`|End macro

macro parameters start with # and are numbered from 1.

Example:
```    
    MACRO SET
    SETH	#1, /#2
    SETL	#1, #2
    ENDM

    SET V0, $1234
```

[Top](#microcpu---16-bit-risc-cpu-version-2)

### Assembler procedures

Directive | Description
---------|-----------
`<label> PROC`|Start procedure
`GLOBAL <label>[,<label>...]`|Add local procedure label as global
`ENDP`|End procedure

Example:
```
get_one PROC
    SET V0, 1
    ADD PC, LR, 3
    ENDP
	
get_1 PROC
    GLOBAL get_2
    SET V0, 1
return ADD PC, LR, 3
get_2 SET V0, 2
    B return
    ENDP
```

`GLOBAL` controls procedure-local label visibility. It is not an object export
directive; use `PUBLIC` to export symbols from an object file.

[Top](#microcpu---16-bit-risc-cpu-version-2)

### Command line options

`microasm [--cpu original|j11|ucode] [-verilog|-binary|-object] [--list <file|->] [-D name[=expr]|--define name[=expr]] [-U name|--undef name] <input.asm> [output]`

`microasm [--cpu original|j11|ucode] [-verilog|-binary|-obj] [--list=<file|->] [-Dname[=expr]|--define=name[=expr]] [-Uname|--undef=name] <input.asm> [output]`

* -verilog - create verilog ram file
* -binary  - create binary file
* -object, -obj - create object file
* --cpu original\|j11\|ucode - select the native ISA; default `original`
* --list-cpus - list the supported native profiles
* --list <file|-> - write the assembly listing to a file, or to stdout with `-`
* -D, --define - define a global constant before pass 1. If value is omitted,
  it defaults to 1. The expression may reference earlier command-line defines.
* -U, --undef - remove a command-line define before pass 1.

By default, the output file is a hex file and no listing is printed.
Compilation status and error lines are always printed to stdout and, when
`--list` is used, to the listing stream. The final `Constants`, `Labels`, and
`Refs` tables are included only in the listing stream.

Examples:
```
microasm -D DEBUG -D ROM_BASE='$8000' source.asm out.mem
microasm --define=FEATURE_UART=1 --undef DEBUG source.asm
```

[Top](#microcpu---16-bit-risc-cpu-version-2)

### Object files and linker

Object files use a UniCROSS-style format with public symbols, external symbols,
one code segment, and relocation records. `microasm -object` creates object
files; `microlink` links one or more object files into a final image.

`microlink [-verilog|-binary] [-symbols] [-org address] [-o output] <input.obj>...`

* default output is a hex `.mem` file
* -binary - create binary file
* -verilog - create verilog ram file
* -symbols - print the resolved public symbol table to stdout
* -org - set the final load address, default `$0000`
* -o - set output path

`microlink` does not create relocatable output files.

[Top](#microcpu---16-bit-risc-cpu-version-2)

### Disassembler

`microdis [--cpu original|j11|ucode] [-binary|-object] [-org address] <input.bin|input.obj>`

Objects carry a CPU tag; raw binaries require the matching `--cpu` and
default to `original`. `microlink` rejects objects from different profiles.
See [object compatibility](docs/cpu-profiles.md#object-files-and-disassembly).

`microdis` disassembles raw binary files and object files. Input mode is
auto-detected by default; `-binary` and `-object` force a mode. `-org` sets the
base address printed in the listing. Object disassembly prints public labels,
external declarations, entry point information, and relocation comments.

[Top](#microcpu---16-bit-risc-cpu-version-2)

## Bootloader

The original RISC UART bootloader loads, saves and executes native programs.
It is not the J-11 SD bootstrap or a PDP-11 ODT console.

[Top](#microcpu---16-bit-risc-cpu-version-2)

### Bootloader options

* `bootloader <uart port> load <file.bin> [<start address> [<end address>]]`
* `bootloader <uart port> save <file.bin> <start address> <end address>`
* `bootloader <uart port> go [<address>]`

**load** - load a binary file to RAM

**save** - save RAM to a binary file

**go** - execute code

[Top](#microcpu---16-bit-risc-cpu-version-2)

## Lattice Diamond programmer and ftdi jtag dual channel board

See the [Diamond/FTDI guide](docs/diamond.md#programming-with-ft2232).
USB access permissions, the JTAG channel and the UART channel are separate.
Do not unload `ftdi_sio` globally: that also disconnects the UART. If the
kernel owns JTAG channel A, release only that verified interface; preserve B.

[Top](#microcpu---16-bit-risc-cpu-version-2)

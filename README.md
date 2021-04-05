(c) sashz <sashz@pdaXrom.org>, 2020-2021

[GitHub project page](https://github.com/pdaxrom/microcpu)

# MICROCPU - 16-bit RISC CPU (Version 2)

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
  * [Accembler macro definition](#accembler-macro-definition)
  * [Assembler procedures](#assembler-procedures)
  * [Command line options](#command-line-options)
* [Bootloader](#bootloader)
  * [Bootloader options](#bootloader-options)
* [Lattice Diamond programmer and ftdi jtag dual channel board](#lattice-diamond-programmer-and-ftdi-jtag-dual-channel-board)
* [Microcontroller with Lattice MachXO2-1200 microboard](docs/hc1200-mcu.md)
* [Microcomputer with Lattice MachXO2-1200](docs/hc1200-microcomp.md)

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
`GETS <dst>`|`<dst> = <User PC>`|Get user programm counter
`SETS <src>`|`<User PC> = <src>`|Set user programm counter

Examples:
```
    ORG	$0
    B	start
    B	su
    ...
su  SUB SP, SP, 2
    PUSH V0
    GETS V0
    ...
    PUTS V0
    POP  V0
    ADD SP, SP, 2
    SWU
    ...
ini SWS
    ...
```

[Top](#microcpu---16-bit-risc-cpu-version-2)

## Interrupts

The system supports two interrupts - the CPU command to switch to superuser mode (SWS command) and peripheral interrupt (external signal). Both interrupts cause a jump to address $0002 while saving the interrupted address in a special register, which is available for modification using the GETS and PUTS commands. Exit from the interrupt mode is performed using the SWU command. Until the end of the execution of the mode, other interrupts are prohibited.

[Top](#microcpu---16-bit-risc-cpu-version-2)

## MicroAssembler

Assembler has support for macros, procedures. Since the processor has a limited number of instructions, some instructions can be implemented as macros.

[Top](#microcpu---16-bit-risc-cpu-version-2)

### Assembler directives

Directive | Description
----------|-----------
`<symbol> EQU <exp>`|Set a symbol equal to an expression
`DB <imm>[,<imm>...]`|Define constant byte(s)
`DW <imm16>[,<imm16>...]`|Define constant word(s)
`DS <imm16>[,<imm>]`|Reserves num bytes of space and initializes them to val (optional, defaul 0).
`ALIGN <imm>`|Align address to num bits
`ORG <imm16>`|Set location address counter
`INCLUDE <file name>`|Include external source file
`CHKSUM`|Insert constant word to binary to sum all words as $FFFF

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

### Accembler macro definition

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

[Top](#microcpu---16-bit-risc-cpu-version-2)

### Command line options

`microasm [-verilog|-binary] <input.asm> [output]`

* -verilog - create verilog ram file
* -binary  - create binary file

By default, the output file is hex file.

[Top](#microcpu---16-bit-risc-cpu-version-2)

## Bootloader

The bootloader is using to load code and data into RAM, save memory from RAM and run the code .

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

To work correctly with ftdi jtag, remove the ftdi_sio module:

`sudo rmmod  ftdi_sio`

Open the Programmer, reconnect the FTDI board and disconnect the JTAG port:

`./ft2232d-util/ft2232d-ctl`

[Top](#microcpu---16-bit-risc-cpu-version-2)

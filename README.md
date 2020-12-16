(c) 2020 sashz <sashz@pdaXrom.org>

[GitHub project page](https://github.com/pdaxrom/microcpu)

# MICROCPU - 16-bit CPU

* [Registers](#registers)
* [Address modes](#address-modes)
* [Flags](#flags)
* [Instructions](#instructions)
  * [Data Movement Instructions](#data-movement-instructions)
  * [Arithmetic and Logic Instructions](#arithmetic-and-logic-instructions)
  * [Control Flow Instructions](#control-flow-instructions)
* [MicroAssembler](#microassembler)
  * [Assembler directives](#assembler-directives)
  * [Accembler macro definition](#accembler-macro-definition)
  * [Assembler procedures](#assembler-procedures)
  * [Command line options](#command-line-options)
* [Bootloader](#bootloader)
  * [Bootloader options](#bootloader-options)
* [Lattice Diamond programmer and ftdi jtag dual channel board](#lattice-diamond-programmer-and-ftdi-jtag-dual-channel-board)
* [Microcomputer with MachXO2-1200](docs/hc1200-microcomp.md)

## Registers

The processor has eight 16-bit registers. The register 0 (PC) using as program counter.

Numeric|Name|Alias
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
```
15 14 13 12 11 10 09 08 | 07 06 05 04 03 02 01 00
------------------------|------------------------
        HIGH BYTE       |        LOW BYTE
```

[Top](#microcpu---16-bit-cpu)

## Address modes

The processor has 5 addressing modes that can be used by the programmer:

1. Register
2. Immediate
3. Immediate indexed
4. Register indexed
5. Relative

[Top](#microcpu---16-bit-cpu)

## Flags

The processor uses five condition code bits or flags:
Name|Description
----|-----------
`I`|interrupt mask
`C`|carry flag
`Z`|zero flag
`V`|2s complement overflow
`N`|negative

[Top](#microcpu---16-bit-cpu)

## Instructions

Machine instructions generally fall into three categories: data movement, arithmetic/logic, and control-flow.
We use the following notation:
Notation|Description
--------|-----------------------
`<dst>`|Any destination register
`<src>`|Any source register
`<imm>`|8-bit immediate
`<imm16>`|16-bit immediate
`<idx>`|Any register or 4-bit unsigned immediate
`<arg1>`|Any register
`<arg2>`|Any register or 4-bit unsigned immediate
`<rel>`|11-bit signed immediate

[Top](#microcpu---16-bit-cpu)

### Data Movement Instructions

Instruction | |Description
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

[Top](#microcpu---16-bit-cpu)

### Arithmetic and Logic Instructions

Instruction | |Description
------------|-|-----------
`ADD  <dst>, <arg1>, <arg2>`|`<dst> = <arg1> + <arg2>`|Add
`ADDC <dst>, <arg1>, <arg2>`|`<dst> = <arg1> + <arg2>  + flag_C`|Add with carry
`SUB  <dst>, <arg1>, <arg2>`|`<dst> = <arg1> - <arg2>`|Subtract
`SUBC <dst>, <arg1>, <arg2>`|`<dst> = <arg1> - <arg2>  - flag_C`|Subtract with carry
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
    ADDC V1, V2, 5
    SUB V0, V2, V1
    SHR V0, V0, 1
    SXT V1, V1
```

[Top](#microcpu---16-bit-cpu)

### Control Flow Instructions

Instruction | |Description
------------|-|-----------
`CMP <arg1>, <arg2>`|`<arg1> - <arg2>`|Compare
`TST <arg1>, <arg2>`|`<arg2> & <arg2>`|Test bits
`B   <rel>`|`PC = PC + <rel>`|Branch
`BLE <rel>`|`PC = PC + <rel> If Z \| (N ^ V) = 1`|Branch On Less Than Or Equal Zero
`BGE <rel>`|`PC = PC + <rel> If (N ^ V) = 0`|Branch On Greater Than Or Equal Zero
`BEQ <rel>`|`PC = PC + <rel> If Z = 1`|Branch On Equal Zero
`BCS <rel>`|`PC = PC + <rel> If C = 1`|Branch If Carry Set

Examples:
```
    CMP V0, 0
    BEQ exit
    CMP V0, V1
    BLE loop
    TST V0, 4
    BEQ wait
```

[Top](#microcpu---16-bit-cpu)

## MicroAssembler

Assembler has support for macros, procedures. Since the processor has a limited number of instructions, some instructions can be implemented as macros.

[Top](#microcpu---16-bit-cpu)

### Assembler directives

Directive |Description
----------|-----------
`<symbol> EQU <exp>`|Set a symbol equal to an expression
`DB <imm>[,<imm>...]`|Define constant byte(s)
`DW <imm16>[,<imm16>...]`|Define constant word(s)
`DS <imm16>[,<imm>]`|Reserves num bytes of space and initializes them to val (optional, defaul 0).
`ALIGN <imm>`|Align address to num bytes
`ORG <imm16>`|Set location address counter

Examples:
```
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

[Top](#microcpu---16-bit-cpu)

### Accembler macro definition

Directive|Description
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

[Top](#microcpu---16-bit-cpu)

### Assembler procedures

Directive|Description
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

[Top](#microcpu---16-bit-cpu)

### Command line options

`microasm [-verilog|-binary] <input.asm> [output]`

* -verilog - create verilog ram file
* -binary  - create binary file

By default, the output file is hex file.

[Top](#microcpu---16-bit-cpu)

## Bootloader

The bootloader is using to load code and data into RAM, read memory and run the code .

[Top](#microcpu---16-bit-cpu)

### Bootloader options

* `bootloader <uart port> load <file.bin> [<start address> [<end address>]]`
* `bootloader <uart port> load <file.bin> <start address> <end address>`
* `bootloader <uart port> go [<address>]`

**load** - load a binary file to RAM

**save** - save RAM to a binary file

**go** - execute code

[Top](#microcpu---16-bit-cpu)

## Lattice Diamond programmer and ftdi jtag dual channel board

To work correctly with ftdi jtag, remove the ftdi_sio module:

`sudo rmmod  ftdi_sio`

Open the Programmer, reconnect the FTDI board and disconnect the JTAG port:

`./ft2232d-util/ft2232d-ctl`

[Top](#microcpu---16-bit-cpu)

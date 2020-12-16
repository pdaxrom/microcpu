# Microcomputer with Lattice MachXO2-1200

* [Board](#board)
  * [GPIO](#gpio)
  * [UART](#uart)
* [Bootloader](#bootloader)
* [Examples](#examples)
  * [UART](#uart)
  * [LED Matrix](#led-matrix)
  * [LED Display](#led-display)
  
[Back to main page](..)

## Board

The system uses a [microfpga board](https://github.com/pdaxrom/microfpga-demo)

<img src="microfpga.jpg" width="320" />

Implemented 15 bit I/O port, UART and RESET signal. The default configuration includes 2KB of RAM, pre-initialized with [bootloader](#bootloader) code.

[Top](#microcomputer-with-lattice-machxO2-1200)

### UART

The UART has a fixed baud rate of 115200.

Address | Description
-|-
$E6B0|Status
$E6B1|Data

Status bit | Description
-|-
0|Byte received
1|Byte transmitting

[Top](#microcomputer-with-lattice-machxO2-1200)

### GPIO

I/O port uses 15 bits (maximum available pins for this board).

Address | Description
-|-
$E6D0|I/O bits 14..8
$E6D1|I/O bits 7..0
$E6D2|Direction bits 14..8
$E6D3|Direction bits 7..0

Direction bits 1 - output, 0 - input. By default, all bits are input.

[Top](#microcomputer-with-lattice-machxO2-1200)

## Bootloader

The UART bootloader uses 256 bytes of memory (from address 0) and allows you to load, save, and execute code.

Bootloader commands:

Command bytes | Size in bytes | Description
-|-|-
`'L' <start address> <end address>`|`5 + (<end address> - <start address>)`|Loading code into RAM
`'S' <start address> <end address>`|`5 + (<end address> - <start address>)`|Saving code from memory
`'G' <start address>`|`3`|Execute code from start address

The loader contains the following subroutines:

Address | Description
-|-
`$0000`|RESET
`$0006`|Get char from UART to register V0
`$0008`|Put char to UART from register V0
`$000A`|Put string to UART (V0 is pointer to null-terminated string)

[Top](#microcomputer-with-lattice-machxO2-1200)

## Examples

The examples are compiled by a microassembler and loaded by the bootloader via UART.

[Top](#microcomputer-with-lattice-machxO2-1200)

### UART

Example of use UART [printuart.asm](../asm/examples/microcomp/printuart.asm)

<img src="uart.jpg" width="320" />

[Top](#microcomputer-with-lattice-machxO2-1200)

### Led Matrix

Example of use with led matrix (MAX7219) [matrix.asm](../asm/examples/microcomp/matrix.asm)

<img src="matrix.jpg" width="320" />

[Top](#microcomputer-with-lattice-machxO2-1200)

### Led Display

Example of use with led matrix display [hcms.asm](../asm/examples/microcomp/hcms.asm)

<img src="hcms.jpg" width="320" />

[Top](#microcomputer-with-lattice-machxO2-1200)

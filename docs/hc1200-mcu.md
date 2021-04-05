# Microcontroller with Lattice MachXO2-1200 microboard

* [Board](#board)
  * [UART](#uart)
  * [GPIO](#gpio)
  * [TIMER](#timer)
* [Bootloader](#bootloader)
* [Examples](#examples)
  * [UART I/O](#uart-io)
  * [LED Matrix](#led-matrix)
  * [LED Display](#led-display)
  
[Back to main page](..)

## Board

The system uses a [microfpga board](https://github.com/pdaxrom/microfpga-demo)

<img src="microfpga.jpg" width="320" />

Implemented 15 bit I/O port, UART, TIMER and RESET signal. The default configuration includes 6KB of RAM, pre-initialized with [bootloader](#bootloader) code.

[Top](#microcontroller-with-lattice-machxo2-1200-microboard)

### UART

The UART has a fixed baud rate of 115200.

Address | Description
-|-
$FFE0|Status
$FFE1|Data

Status bit | Description
-|-
0|Byte received
1|Byte transmitting

[Top](#microcontroller-with-lattice-machxo2-1200-microboard)

### GPIO

I/O port uses 15 bits (maximum available pins for this board).

Address | Description
-|-
$FFE8|I/O bits 14..8
$FFE9|I/O bits 7..0
$FFEA|Direction bits 14..8
$FFEB|Direction bits 7..0

Direction bits 1 - output, 0 - input. By default, all bits are input.

[Top](#microcontroller-with-lattice-machxo2-1200-microboard)

### Timer

Address | Description
-|-
$FFF0|Initial value bits [7:0]
$FFF1|Initial value bits [15:8]
$FFF2|Status

Status bits: 1 - countdown finished, 0 - interrupt.
The interrupt bit is cleared after reading the status register.

[Top](#microcontroller-with-lattice-machxo2-1200-microboard)

## Bootloader

The UART bootloader uses 256 bytes of memory (from address 0) and allows you to load, save, and execute code.

Bootloader commands:

Command bytes | Size in bytes | Description
-|-|-
`'L' <start address> <end address>`|`5 + (payload)`|Loading code into RAM
`'S' <start address> <end address>`|`5 + (<end address> - <start address>)`|Saving code from memory
`'G' <start address>`|`3`|Execute code from start address

Data is transmitted to the bootloader in packets of 14 bytes, after which a sync byte is received.

The loader contains the following subroutines:

Address | Description
-|-
`$0000`|RESET
`$0008`|WARM UP
`$000C`|Get char from UART to register V0
`$000E`|Put char to UART from register V0
`$0010`|Put string to UART (V0 is pointer to null-terminated string)

[Top](#microcontroller-with-lattice-machxo2-1200-microboard)

## Examples

The examples are compiled by a microassembler and loaded by the bootloader via UART.

[Top](#microcontroller-with-lattice-machxo2-1200-microboard)

### UART I/O

Example of use UART [printuart.asm](../asm/examples/printuart.asm)

<img src="uart.jpg" width="320" />

[Top](#microcontroller-with-lattice-machxo2-1200-microboard)

### Led Matrix

Example of use with led matrix (MAX7219) [matrix.asm](../asm/examples/matrix.asm)

<img src="matrix.jpg" width="320" />

[Top](#microcontroller-with-lattice-machxo2-1200-microboard)

### Led Display

Example of use with led matrix display [hcms.asm](../asm/examples/hcms.asm)

<img src="hcms.jpg" width="320" />

[Top](#microcontroller-with-lattice-machxo2-1200-microboard)

# FPGA J-11 microengine

This branch develops a J-11-compatible CPU as firmware running on a small
16-bit RISC microengine. The guest architecture is intentionally kept out of
the Verilog instruction decoder: PDP-11 opcodes, effective addresses, flags,
traps, and interrupts will be implemented by replaceable microcode.

## Version 1 scope

- 16-bit PDP-11 address space
- no MMU or split I/D space
- one J-11 register set
- guest RAM backed by the board's 128 KiB SPI FRAM
- integer instruction set first
- FP11, CIS, and memory management deferred

## Data paths

```text
16-bit uROM -> microengine RISC ALU -> guest context
                         |
                         +-> transactional guest bus -> I/O page router
                                                        |-> SPI FRAM
                                                        `-> DL11 UART
```

Microcode instruction fetches never use the guest bus. The uROM is intended
to infer 16-bit EBR storage, while guest memory transactions use a separate
request/ready interface.

The current production uROM is 2048 x 16 bits and therefore uses four MachXO2
9-kbit EBRs. The original 1024-word image was filled completely by the resident
integer core, so the deeper image leaves room for the remaining non-MMU
instructions without weakening guest semantics. Unsupported opcodes retain the
architectural reserved-instruction trap path.

## Guest context

The first implementation provides sixteen 16-bit context words:

| Index | Meaning |
|---:|---|
| 0..7 | J-11 R0..R7 |
| 8 | J-11 PSW |
| 9 | current J-11 instruction word |
| 10 | latched cause: `1` bus/address error, `2` reserved instruction, `3` HALT |
| 11 | pending IRQ: bit 15 valid, bits 10..8 level, bits 7..0 vector |
| 12..13 | reserved microcode scratch/state |
| 14 | pre-instruction T-bit snapshot used by TRACE/RTI/RTT |
| 15 | write-only microcode control; bit 0 pulses guest peripheral RESET |

`GGET` and `GSET` are microengine-only aliases for the old `SWS` and `SWU`
opcode groups. They move values between RISC registers and the guest context.
The original `cpu.v` behavior is unchanged.

## Guest bus

The microengine exposes a level-held transaction:

```text
guest_req, guest_write, guest_byte, guest_bank
guest_address[15:0], guest_wdata[15:0]
guest_rdata[15:0], guest_ready, guest_error
```

The request remains asserted until `guest_ready`. Word and byte transfers are
single guest operations even though the SPI controller serializes their bytes.
An odd-address word access completes locally with `guest_error` and does not
touch the FRAM. Failed transactions redirect the micro-PC to its fixed `0002`
ABI entry; production microcode then enters PDP-11 bus/address-error vector
`004` instead of continuing the failed operation.

## FRAM layout

| Physical range | Initial use |
|---:|---|
| `00000..0dfff` | 56 KiB guest RAM visible without an MMU |
| `0e000..0ffff` | PDP-11 I/O page overlay |
| `10000..1ffff` | reserved for images, snapshots, or firmware staging |

The J-11 I/O page overlays the top of guest bank 0 in the board-level bus
router. FRAM storage remains physically present underneath that window but is
not visible to guest accesses. Unmapped I/O-page accesses currently complete
with a bus error. Bank 1 bypasses the I/O overlay and remains available to
microcode for staging and snapshots.

The first guest device is a DL11-compatible console:

| Octal address | Hex address | Register |
|---:|---:|---|
| `0177560` | `ff70` | receiver CSR |
| `0177562` | `ff72` | receiver buffer |
| `0177564` | `ff74` | transmitter CSR |
| `0177566` | `ff76` | transmitter buffer |

DONE and IE use the standard bits 7 and 6. RX and TX request vectors `060` and
`064` respectively, both at BR4. The existing physical 115200-baud UART is used
underneath.

The controller uses the command sequence already used by the bootloader:

- read: `03`, three address bytes, one or two data bytes
- write enable: `06`
- write: `02`, three address bytes, one or two data bytes

Address byte 16 is supplied by `guest_bank`; upper address bits are zero.
Words are stored little-endian.

## Current implementation

- `rtl/j11_microengine.v`: separate uROM, original RISC ALU/control subset,
  guest context, IRQ latch, and stalled guest-memory operations
- `rtl/spi_fram_guest_ram.v`: byte/word SPI FRAM transaction engine
- `boards/hc1200-microcomp/j11_microcomp.v`: HC1200 board top-level with the
  physical MOSI, MISO, SCK, and CS pins dedicated to guest RAM
- `boards/hc1200-microcomp/j11_guest_bus.v`: 56 KiB FRAM window, PDP-11 I/O
  overlay, DL11 register adaptation, and interrupt vectors
- `boards/hc1200-microcomp/microcomp-j11.ldf`: separate Diamond project; the
  original `microcomp.ldf` and its firmware-controlled GPIO design remain
  available
- `testbench/spi_fram_model.v`: behavioral 128 KiB FRAM model
- `testbench/tb_spi_fram_guest_ram.v`: byte, word, bank, endian, and odd-address
  checks
- `testbench/tb_j11_microengine.v`: end-to-end microcode/context/FRAM smoke test
- `testbench/tb_j11_fetch.v`: guest instruction fetch and PC increment
- `testbench/tb_j11_execute.v`: assembled PDP-11 instruction tests, including
  word/byte effective addresses, register side effects, and condition flags
- `testbench/tb_j11_guest_bus.v`: FRAM/I/O overlay, DL11 status/TX/IRQ, bus
  error, and service-bank checks
- `testbench/board/tb_board_j11_microcomp.v`: verifies the same transaction
  through the actual HC1200 top-level package pins

## HC1200-microcomp configuration

Open `boards/hc1200-microcomp/microcomp-j11.ldf` in Diamond. It targets the
same `LCMXO2-1200HC-4SG32C` device and reuses `microcomp.lpf`, so all package
pin assignments stay identical to the existing board project.

In this configuration `gpio_mosi`, `gpio_miso`, `gpio_msck`, and `gpio_mcs`
are no longer software GPIO. They are wired directly to
`spi_fram_guest_ram`. At the 26.6 MHz internal oscillator and the default
divider of two, FRAM SCK is approximately 6.65 MHz. The board UART is exposed
as the DL11 console. The four generic GPIO pins are high impedance, and the
display is blanked until their PDP-11 I/O-page mappings are implemented.

Production microcode source is maintained only as assembler in
`ucode/j11.asm`. `boards/hc1200-microcomp/j11_ucode.mem` is generated from it; it
must not be edited by hand. Rebuild the Diamond image with:

```sh
make -C boards j11-ucode
```

The current hardware microprogram fetches guest words through the FRAM bus,
stores each opcode in the guest IR context word, and advances guest PC. Its
resident decoder implements `NOP`, `SWAB`, `SXT`, `MOV/MOVB`, `CMP/CMPB`,
`BIT/BITB`,
`BIC/BICB`, `BIS/BISB`, `XOR`, `MUL`, `DIV`, `ASH`, `ASHC`, `TSTSET`,
`WRTLCK`, `ADD`, `SUB`, `CLR/CLRB`, `COM/COMB`, `INC/INCB`,
`DEC/DECB`, `NEG/NEGB`, `ADC/ADCB`, `SBC/SBCB`, `ROR/RORB`, `ROL/ROLB`,
`ASR/ASRB`, `ASL/ASLB`, `TST/TSTB`, `MFPS`, `MTPS`, all
sixteen PDP-11 branch
conditions (`BR`, `BNE`, `BEQ`, `BGE`, `BLT`, `BGT`, `BLE`, `BPL`, `BMI`,
`BHI`, `BLOS`, `BVC`, `BVS`, `BCC`, and `BCS`), and the condition-code group
`CLC/CLV/CLZ/CLN/CCC/SEC/SEV/SEZ/SEN/SCC`. `JMP`, `JSR`, `RTS`, and `SOB`
provide subroutine and loop control flow. `BPT`, `IOT`, `EMT`, and `TRAP` enter
their architectural vectors through the common trap path, and `HALT` enters
the stopped path. `WAIT` stalls until an interrupt request is latched, `MFPT`
reports DCJ11 processor type 5 in R0, and `SPL` updates only `PSW[7:5]` in the
current single-mode configuration. Kernel-mode `RESET` clears the latched IRQ
and resets the DL11 state without erasing or resetting the FRAM; RESET in a
non-kernel current mode is a NOP.
Reserved instructions enter PDP-11 vector `010`, save the post-instruction PC
and old PSW on the guest stack, and can return with `RTI` or `RTT`. The engine
snapshots T when it fetches each guest instruction, gives TRACE vector `014`
priority at the following instruction boundary, traces immediately when RTI
restores T, and implements RTT's one-instruction trace suppression. Version 1
currently uses the reserved-instruction path only as an architectural trap; no
guest instruction emulator is installed.
Latched external interrupts are accepted at guest instruction boundaries and
enter the supplied even vector through the same stack-frame path. The engine
latches the three-bit BR level with the vector and accepts it only when that
level is strictly greater than `PSW[7:5]`; a masked request remains pending.

The common `ea_resolve` micro-subroutine implements all PDP-11 addressing modes
0 through 7. It consumes extension words, applies register side effects once,
uses a one-byte autoincrement/autodecrement step for R0..R5 byte operations,
and retains the two-byte step for SP, PC, and deferred modes. `MOV`, `MOVB`,
`SWAB`, `SXT`, `CLR`, `CLRB`, `COM`, `COMB`, `INC`, `INCB`, `DEC`, `DECB`,
`NEG`, `NEGB`,
`ADC`, `ADCB`, `SBC`, `SBCB`, `ROR`, `RORB`, `ROL`, `ROLB`, `ASR`, `ASRB`,
`ASL`, `ASLB`, `TST`, `TSTB`, `CMP`, `CMPB`, `BIT`, `BITB`, `BIC`, `BICB`,
`BIS`, `BISB`, `XOR`, `ADD`, `SUB`, `TSTSET`, `WRTLCK`, `MFPS`, and `MTPS` all use this shared
resolver.
`MOVB` performs the PDP-11 sign extension on register destinations, while
`CLRB`, `COMB`, `INCB`, `DECB`, `NEGB`, `ADCB`, `SBCB`, `BICB`, and `BISB`
preserve the register's high byte; the byte shift/rotate group does the same.
`INC/DEC` replace `N/Z/V` for the selected word or byte width while preserving
the previous carry flag. `NEG`, `ADC`, and `SBC` replace all four arithmetic
flags, including the zero-carry cases. Shifts and rotates use the outgoing bit
as `C` and compute the architectural `V = N xor C`.
`SUB`
explicitly normalizes the
resolver's working width flag because its opcode has bit 15 set despite being
word-only. All instruction behavior lives in `ucode/j11.asm`, not in the
Verilog opcode decoder.
`SWAB` performs a word read/modify/write through the same resolver, derives
`N/Z` from the swapped result's low byte, and clears `V/C`.
`SXT` writes zero or all ones according to the previous `N`, updates `N/Z`,
clears `V`, and preserves `C`. `MFPS` uses byte destination addressing, sign
extends register results, updates `N/Z`, clears `V`, and preserves `C`.
`MTPS` uses byte source addressing, updates priority and `NZVC`, and preserves
the old `T` bit and upper PSW. With the current single-mode configuration it
uses the DCJ11 kernel-mode behavior.
`XOR` reuses the word destination path and preserves `C` while updating `N/Z`
and clearing `V`.
`MUL` snapshots its R operand before source-EA side effects, then performs a
signed 16-by-16 multiply as a 16-step shift-add loop using only the base
microengine ALU. It writes the architectural high/low register pair and derives
`N/Z/C` from the full 32-bit product; an odd R retains the DCJ11 low-word
overwrite behavior. No Verilog multiplier is instantiated.
`ASH` interprets the source's low six bits as the signed EIS shift count and
uses repeated one-bit ALU shifts. It snapshots R before resolving the source EA,
tracks every sign transition for `V`, and retains the final outgoing bit as `C`.
`ASHC` applies the same rules to the full R:R|1 pair, including pre-EA pair
sampling and the DCJ11 odd-register overwrite behavior.
`DIV` uses a 32-step restoring divide over the same 16-bit ALU. It implements
signed quotient and remainder rules, divide-by-zero and signed-word overflow,
pre-EA dividend sampling, and the DCJ11 odd-register result convention.
`MARK` implements the PDP-11 stack-frame teardown sequence. `TSTSET` and
`WRTLCK` implement the DCJ11 memory-only lock operations; the present
single-master guest bus keeps each microcoded read/modify/write instruction
uninterrupted at guest instruction boundaries.

`JMP` and `JSR` also use `ea_resolve`, including indexed and deferred modes.
Register-direct mode 0 is rejected before applying any side effects: `JMP`
enters vector `004`, while the DCJ11 `JSR` behavior enters reserved vector
`010`. The link register for `JSR` is sampled after destination EA side effects
and the saved return PC includes its extension word. `RTS SP` and `RTS PC`
retain their architectural register-alias ordering.

For the DCJ11 model, a register-direct source is sampled after a non-register
destination EA has been resolved. Thus `MOV R1,(R1)+` stores the incremented
value, and `MOV PC,X(Rn)` sees PC after the destination extension word. The
shared MOV and double-operand paths implement this late sampling for word and
byte operations. `testbench/j11_programs/ea_timing.asm` covers autoincrement,
autodecrement, deferred, indexed-PC, compare, bit-test, and add cases.

## Reserved-instruction handling

The invalid-instruction path uses architectural vector `010`. On handler entry
`(SP)` is the saved PC immediately after the unsupported opcode word and
`2(SP)` is the saved PSW. The handler may diagnose or terminate the program and
can return through `RTI` if it deliberately handles the condition.

The resident decoder has not consumed extension words when it rejects an
opcode. `testbench/j11_programs/reserved.asm` verifies vector entry, the guest
stack frame, and `RTI`, without implementing instruction emulation. Arithmetic
single-operand instructions selected for version 1 are resident: `inc_dec.asm`
and `neg_adc_sbc.asm` cover their byte/word boundary flags, carry behavior,
register preservation, and memory EA side effects.

Guest instruction tests live under `testbench/j11_programs` and are also
assembler source. They are built with the external `microasm11` using the
`dcj-11` CPU profile, converted to byte-oriented `$readmemh` images, and then
loaded into the behavioral FRAM. No PDP-11 instruction bytes are written by
hand in the Verilog tests. The default sibling checkout can be overridden:

```sh
make -C testbench j11-test MICROASM11_DIR=/path/to/microasm11
```

The board-level RTL path is covered by Icarus Verilog. A Diamond synthesis
and place-and-route run is still required to record final LUT, EBR, timing,
and SPI-clock margins on the physical MachXO2-1200 target.

Run the new tests with:

```sh
make -C testbench j11-test
```

## Next implementation steps

1. Add a short sequential-read buffer so instruction fetches do not start a
   new SPI command and address phase for every word.
2. Differentially compare each guest step with the existing C J-11 core.

The present SPI controller favors simple, testable semantics over throughput.
It opens a new SPI transaction for every request; burst/prefetch support is a
planned optimization after the guest bus and I/O overlay are stable.

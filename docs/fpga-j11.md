# FPGA J-11 microengine

This branch develops a J-11-compatible CPU as firmware running on a small
16-bit RISC microengine. The guest architecture is intentionally kept out of
the Verilog instruction decoder: PDP-11 opcodes, effective addresses, flags,
traps, and interrupts are implemented by replaceable microcode.

This boundary includes processor-owned I/O registers and the guest timer CSR:
their address decoding, masks, and side effects belong in assembly, not in a
J-11-specific Verilog state machine. The existing microengine is the execution
mechanism, not a second implementation of J-11 architectural behavior.

## Version 1 scope

- 16-bit PDP-11 address space
- no MMU or split I/D space
- one J-11 register set
- banked kernel/supervisor/user stack pointers (follow-up to the V1 milestone)
- guest RAM backed by the board's 128 KiB SPI FRAM
- integer instruction set first
- FP11, CIS, and memory management deferred; FIS conditional on remaining uROM

The agreed priority instruction checklist and active acceptance work are in
[`TODO.md`](../TODO.md#j-11-v1-active-plan-no-mmu). The user-authorized follow-up
adds existing C-core fixture replay, SP banks, processor-owned I/O registers,
and FIS only if it fits. MMU and FP11 remain outside the active scope.

## Data paths

```text
16-bit uROM -> microengine RISC ALU -> guest context
                         |
                         +-> microcoded memory/DL11/LTC dispatcher
                                      |-> transactional SPI FRAM
                                      `-> raw UART/time service interface
```

Microcode instruction fetches never use the guest bus. The uROM is intended
to infer 16-bit EBR storage, while guest memory transactions use a separate
request/ready interface.

The current production uROM is 2560 x 16 bits, with 2529 words occupied and
31 free after the microcoded UART/LTC step. `ucode/config.mk` supplies the image
size to both Makefiles; the board top-level parameter has the same default.
This enlarged image has been simulated on the Mac, not synthesized or placed
in Diamond. Actual FPGA resource use and timing remain unverified for this
revision. Unsupported opcodes retain the reserved-instruction trap path.

## Guest context

The microengine provides thirty-two 16-bit context words in one synchronous
context RAM. Immediate and register-indexed accesses both use a five-bit index:

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
| 16, 17, 19 | inactive KSP, SSP, USP; active SP lives in R6 |
| 18 | saved native ALU flags across a guest store |
| 20, 21, 22 | software DL11 RCSR, RBUF, XCSR; CSR bit 8 is a private IRQ latch |
| 23, 24 | software LTC CSR and last observed native tick sequence |
| 25..31 | non-reentrant memory-helper scratch/return state |

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

The J-11 I/O page overlays the top of guest bank 0. Microcode decodes the
guest devices; the board excludes this range from ordinary FRAM requests.
FRAM storage remains physically present underneath that window but is
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
`064` respectively, both at BR4; RX wins a tie. All these registers and requests
are implemented in `ucode/j11_memory.asm` and `ucode/j11_peripherals.asm`.
Acknowledging a UART interrupt clears its request, not DONE. A DONE transition
or an IE rising edge with DONE already set can create a new request. Disabling
IE removes the request. RBUF low-byte read/write or RCSR RE clears receive DONE.
High-byte accesses read zero and do not affect the low-byte CSR/data state.
XCSR BREAK and maintenance loopback are supported through raw pin controls.

This is the minimal console profile for future ODT polling, not every DL11
modem/error feature: framing/parity/overrun reporting and modem signals remain
unimplemented. Physical framing is 115200 baud, 8N1, configured by the existing
Verilog `BAUD` parameter. Runtime baud switching is not required by the classic
DL11 register interface: its speed selection was hardware-configured (DEC
[DL11 manual, section 2.5](https://www.bitsavers.org/www.computer.museum.uq.edu.au/pdf/DEC-11-HDLAA-B-D%20DL11%20Asynchronous%20Line%20Interface%20Manual.pdf)).
ODT itself is still future microcode work.

### Private native services

| Hex address | Native operation |
|---:|---|
| `f000` | Read RX-available bit 0 / TX-ready bit 1; acknowledge event latch |
| `f002` | Read/consume RX byte or write/submit TX byte |
| `f004` | Read free-running 16-bit elapsed-tick sequence |
| `f006` | UART reset pulse bit 0, TX space/BREAK bit 1, loopback bit 2 |

Guest accesses to `f000..f007` trap through vector `004`. Only the firmware
uses native loads/stores here; every guest access, including opcode fetches,
indirect pointers and stack transfers, goes through the software dispatcher.
The board service notification uses BR0/vector0 on the existing microengine
IRQ input. It is consumed by firmware, never delivered to the guest. Hardware
signals RX availability, TX completion and elapsed time; it does not encode
guest UART/LTC addresses, enables, priorities or vectors. Event-free instruction
boundaries skip native status/time reads. RX remains signaled while a physical
byte is held behind an occupied software receive buffer.

Memory helpers preserve live RISC registers except the load destination and
save native ALU flags before stores. They use a single context scratch frame:
device handlers must not call them recursively. Peripheral service runs only
at instruction boundaries or while WAIT is active.

### Planned microcoded processor I/O (not implemented yet)

The reference is `k1801vm1/core/core.c`, built with `ENABLE_MMU=0` and its
default disabled `DCJ_REG_RSVD_ENABLED` option. The following is the intended
software-visible map, not a statement that these accesses currently work:

| Octal address | Register | Reference behavior |
|---:|---|---|
| `177744` | MEMERR | Read state; any write clears |
| `177746` | CCR | Read/write storage; no physical cache in this target |
| `177750` | MAINT | Read-only configuration |
| `177752` | HITMISS | Read-only; no cache activity |
| `177766` | CPUERR | Read mask `000374`; any write clears |
| `177772` | PIRQ | Request bits 15..9, encoded highest priority; vector `240` |
| `177776` | PSW | Explicit writes preserve T; mode changes switch SP banks |

The C model's programmable STKLIM is **not** a DCJ11 feature. The target has
the fixed kernel stack boundary `0400`, per DEC
[DCJ11 User's Guide, section 1.8](https://www.bitsavers.org/pdf/dec/pdp11/1173/EK-DCJ11-UG-PRE_J11ug_Oct83.pdf).
Yellow/red stack traps are still pending with CPUERR; the current image does
not yet enforce that boundary. Address `177774` remains unmapped and its
bus-error behavior is covered by the peripheral guest test.

MMR0/1/2 at `177572/177574/177576`, MMR3 at `172516` (alias `177516`), and
the supervisor/kernel/user PAR/PDR ranges are also pending. The C model's
no-MMU stubs are a reference to review, not an implemented FPGA feature.
The optional reserved-register addresses are not enabled merely because a test
backend happens to accept them.

### Microcoded timer and reference difference

The reference device is in `k1801vm1/lsi11/dev_kw11.c`, not `core/core.c`.
The J-11 target uses the KDJ11-B LTC interface: CSR `177546`, interrupt
vector `100`, priority BR6, LCM bit 7, LCIE bit 6. The source is DEC
[KDJ11-B CPU Module User's Guide, section 1.9 / Table 1-23, printed page 1-45](https://www.bitsavers.org/pdf/dec/pdp11/1173/EK-KDJ1B-UG_KDJ11-B_Nov86.pdf).

There is a material mismatch with the current C device: the manual specifies
that INIT sets LCM and clears LCIE; a clock edge sets LCM; interrupt acknowledge
or writing zero clears LCM. It does not specify a read-to-clear CSR. The C
device currently clears LCM and the request on a low-byte read, but its IRQ
acknowledgement clears only the request. The new assembly tests use the
documented board behavior; the reference C device has not been changed.

Guest timer registers, enables and interrupt processing are microcode. A raw
counter advances once per `TICK_DIVISOR` FPGA clocks (default 443333, nominally
60 Hz at 26.6 MHz) independently of SPI stalls and WAIT. Guest RESET does not
reset elapsed time. Firmware coalesces missed ticks into LCM, handles the
16-bit sequence wrap, and acknowledges LCM before entering vector `100`.
BR6 outranks UART BR4; equal or higher PSW IPL masks a request. A masked WAIT
does not fetch the following instruction. This adds no changes to `cpu.v` or
`j11_microengine.v`.

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
- `boards/hc1200-microcomp/j11_guest_bus.v`: 56 KiB FRAM window and raw UART,
  elapsed-time counter, and native event notification; no guest CSR semantics
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
- `testbench/tb_j11_guest_bus.v`: raw UART/loopback/BREAK, elapsed time,
  notifications, unmapped I/O, and service-bank checks
- `testbench/tb_j11_peripherals.v`: assembled guest CSR/IRQ/WAIT/RESET tests,
  actual UART pin decoding, deterministic ticks and private-address isolation
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
`WRTLCK`, `MFPI`, `MFPD`, `MTPI`, `MTPD`, `ADD`, `SUB`, `CLR/CLRB`,
`COM/COMB`, `INC/INCB`,
`DEC/DECB`, `NEG/NEGB`, `ADC/ADCB`, `SBC/SBCB`, `ROR/RORB`, `ROL/ROLB`,
`ASR/ASRB`, `ASL/ASLB`, `TST/TSTB`, `MFPS`, `MTPS`, all
sixteen PDP-11 branch
conditions (`BR`, `BNE`, `BEQ`, `BGE`, `BLT`, `BGT`, `BLE`, `BPL`, `BMI`,
`BHI`, `BLOS`, `BVC`, `BVS`, `BCC`, and `BCS`), and the condition-code group
`CLC/CLV/CLZ/CLN/CCC/SEC/SEV/SEZ/SEN/SCC`. `JMP`, `JSR`, `RTS`, and `SOB`
provide subroutine and loop control flow. `BPT`, `IOT`, `EMT`, and `TRAP` enter
their architectural vectors through the common trap path, and kernel `HALT`
enters the stopped path. `WAIT` stalls until an eligible interrupt is accepted, `MFPT`
reports DCJ11 processor type 5 in R0, and `SPL` updates only `PSW[7:5]` in the
kernel current mode; it is a NOP in supervisor or user mode. Kernel-mode
`RESET` clears the latched IRQ, resets DL11 and initializes LTC without erasing
FRAM or resetting elapsed time; RESET in a non-kernel current mode is a NOP.
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
All vector entries force the current mode to kernel and copy the interrupted
current mode into the previous-mode field. A non-kernel `HALT` enters vector
`004`; a kernel `HALT` stops the engine. Outside kernel mode, `RTI` and `RTT`
treat `PSW[15:11]` as set-only and preserve the old interrupt priority. The
reserved current-mode encoding 2 follows the DCJ11 rule and is treated as
kernel. Mode changes save the outgoing SP and select KSP/SSP/USP. Trap frames
are pushed on KSP; RTI/RTT pop the current frame before switching to the
restored mode's stack. Reset clears inactive banks, which guest code can
initialize through previous-mode SP writes.

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
the old `T` bit and upper PSW. In supervisor or user mode it also preserves the
old interrupt priority, as required by the DCJ11 privilege rules.
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
Without an MMU or split I/D, `MFPI/MFPD/MTPI/MTPD` deliberately use the same
unified guest address space and single register set. Their EA-before-stack
ordering, push/pop behavior, SP/PC aliases, and condition codes remain
architectural, leaving only mode-space selection for a future MMU version.
Register-direct SP accesses select the previous-mode bank, with PM=2 selecting
USP as a J-11 MxPI special case. This differs from CM=2, which selects KSP.

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

## Deferred follow-up candidates

These are not part of the active V1 instruction plan in `TODO.md` and are not
to be started automatically after its acceptance checks pass.

1. Add a short sequential-read buffer so instruction fetches do not start a
   new SPI command and address phase for every word.
2. Differentially compare each guest step with the existing C J-11 core.

The present SPI controller favors simple, testable semantics over throughput.
It opens a new SPI transaction for every request; burst/prefetch support is a
planned optimization after the guest bus and I/O overlay are stable.

# Specialized microcode engine (`--cpu ucode`)

[Legacy CPU / main README](../README.md) · [Preserved J-11 engine](fpga-j11.md) ·
[Hardware variants](hc1200-microcomp-ucode.md) · [ISA comparison](cpu-profiles.md)

This is the third native CPU profile: [rtl/ucode_cpu.v](../rtl/ucode_cpu.v).
Its independent firmware starts at [ucode/v2/j11.asm](../ucode/v2/j11.asm).
It is optimized for emulating a guest ISA, currently J-11 without MMU. The
original `cpu.v` and preserved `j11_microengine.v`/firmware are not replaced.
The directory name `v2` identifies the newer microcode implementation, not a
fourth CPU or the original RISC's historical "Version 2" name.

## Native engine

The engine has eight 16-bit working registers, PC/SP/LR/V0..V4. These are
**not** the guest PDP-11 registers. The guest registers, alternate R0..R5
set, K/S/U stack pointers, PSW and device state are maintained by assembly in
the shared 64-word context area; guest stack contents are in SPI FRAM.

Compared with the preserved engine:

- `LDI8` loads a zero-extended byte constant in one instruction.
- `GGET/GSET` address all 64 context words directly; indexed access remains.
- One-word absolute `CALL`, `JMP` and `RET` replace longer transfer macros.
- `ADC/SBC` use native carry/borrow for multiword arithmetic, including FIS.
- `CBZ/CBNZ` test a register without changing NZVC; range is -32..31 words.
- The internal PC is a 12-bit word address. Assembly labels, LR and indirect
  targets remain byte addresses; ordinary native instructions take six clocks.
- Original supervisor instructions and native `MOVL/MOVH` are absent. PC
  destinations are limited to `MOV`, `GGET` and `GGETR`. Guest `MOVB` remains.

Native `SUBB` is an internal byte-flag helper, not a PDP-11 byte SUB opcode.
Context indexes 10, 11 and 15 are native cause/IRQ/control service ports;
the ordinary context words are RAM. Exact encodings, flags, PC rules and
version-4 object compatibility are in [CPU profiles](cpu-profiles.md).

## Firmware and hardware boundary

Guest instruction decode, effective addresses, PSW, traps, register/SP banks,
HALT, processor I/O registers, DL11, KW11-L and RK611 behavior are **assembly**.
Verilog supplies generic execution, byte/word FRAM transactions, raw UART,
elapsed ticks and SPI-byte services. It does not decode J-11 guest opcodes.

Current guest features include word/byte integer instructions and addressing
modes, EIS (`MUL`, `DIV`, `ASH`, `ASHC`), FIS, previous-mode moves in unified
memory, two general-register sets, K/S/U SP banks and HALT/Proceed groundwork.
Kernel stack protection uses the fixed octal `0400` boundary, not a fabricated
STKLIM register. See [the instruction checklist](../TODO.md).

The no-MMU configuration exposes 56 KiB of guest RAM. MMU-register probes
take vector 4 with CPUERR.TMO; they are not successful zero-read stubs.
MAINT at octal `177750` reads `000020` (module ID 1, FPA absent), and MFPT
returns 5. This identifies a KDJ11-A-compatible module, not a complete
implementation of its MMU, FP11, cache or console ROM.

ODT, MMU/split I/D, FP11 and CIS remain deferred. The private HALT mailbox is
not a terminal ODT. FIS is a separate extension and does not imply FP11/FPA.
RT-11's `Floating Point Microcode`, `Cache Memory` and `FPU support` lines
must not be treated as functional tests of those options; see
[the identification result](rt11-boot.md#kdj11-a-compatible-identification-2026-08-28).

## Build a selected firmware

From the repository root, with make, a C compiler and Python 3:

```sh
make -C asm
asm/microasm --cpu ucode -binary ucode/v2/j11.asm /tmp/j11-v2.bin

# No-disk J-11 image.
make -C boards j11-v2-ucode

# Current board firmware: SD + FIS + power-on bootstrap.
make -C boards/hc1200-microcomp

# Separate diagnostic images; neither replaces the normal SD image.
make -C boards/hc1200-microcomp diag boot-trace
```

The last three commands generate portable `.mem` and explicit EBR `.v`
initializers without Diamond. Never edit or commit those generated files.
Raw `microasm` output is not a substitute for the board's EBR packing step.
SD boot code is in [rh11_sd.asm](../ucode/experimental/rh11_sd.asm); standalone
transport diagnostics and temporary NOFIS boot trace are in
[ucode/diagnostics/](../ucode/diagnostics/). All use the same `ucode` ISA.

Physical uROM allocation is 3584 16-bit words in seven EBRs. The final 64
words are context RAM, leaving a **3520-word code limit**. At source
`a985039`, SD+FIS+autoboot uses **3501 code + 64 context + 19 free**; boot trace
uses 3443 + 64 + 77. There is no unused EBR for a further uROM bank. The
packer rejects code that overlaps context instead of silently truncating it.

## Simulation and hardware acceptance

```sh
make -C testbench ucode-test ucode-core-test
make -C testbench ucode-fis-reference-test FIS_JOBS=4
make -C testbench -f Makefile.disk hc1200-sd-test
make -C testbench -f Makefile.disk rt11-boot-fast
```

Dependencies, sibling assembler paths and EBR tests are in the
[Icarus/Verilator guide](../testbench/README.md). These commands do not run
Diamond, program the FPGA or write a physical SD card.

Source `a985039` passed the full SD+FIS Diamond build at 26.6 MHz and FLASH
program/verify. The user then confirmed RT-11 boot and `SHOW CONFIGURATION`
on HC1200: `PDP 11/73A Processor`, 56 KiB, EIS, FIS and 50-cycle clock. The
separate full simulation also checks a directory command and unchanged
source-image SHA-256. See [RT-11 acceptance](rt11-boot.md).

That exact `microcomp.ldf` configuration is designated **Stable J11 / RT-11
SD boot**. The [hardware page](hc1200-microcomp-ucode.md) identifies its source,
JED and checksum; no-disk, NOFIS and diagnostic variants are not that baseline.

The complete board uses **1095/1280 LUT4, 548/640 slices, 431 registers and
7/7 EBRs**. TRACE reports 37.627 MHz with zero setup/hold errors at 26.6 MHz;
that is an internal timing estimate, not a tested overclock. External timing
margins and long synchronous disk transfers remain limitations. See
[Diamond evidence](hc1200-sd-diamond.md) and [disk scope](rk611-sd-prototype.md).

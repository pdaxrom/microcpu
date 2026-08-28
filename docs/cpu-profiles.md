# CPU profiles and the specialized microcode engine

## Select the CPU explicitly

`microasm --cpu original|j11|ucode` selects the **native RISC ISA**, not
the guest PDP-11 model. `microasm11 --cpu dcj-11` still assembles guest tests.

| Profile | RTL | Firmware | Purpose |
|---|---|---|---|
| `original` (default) | `rtl/cpu.v` | Existing programs/bootloader | Original native ISA |
| `j11` | `rtl/j11_microengine.v` | `ucode/j11.asm` and its includes | Preserved reference |
| `ucode` | `rtl/ucode_cpu.v` | Independent `ucode/v2/` sources | Specialized engine, first iteration |

The reference RTL and firmware remain unchanged from commit `d4dabf1`.
The v2 firmware and its macro file are independent copies: changing them
does not alter the reference. All executable firmware remains assembly.
Generated binaries, portable ROM images and EBR initialization RTL are build
products, not committed sources.

Examples, from the repository root:

```sh
asm/microasm --list-cpus
asm/microasm --cpu original -binary bootloader/bootldr-mcu.asm /tmp/boot.bin
asm/microasm --cpu j11 -binary ucode/j11.asm /tmp/j11.bin
asm/microasm --cpu ucode -binary ucode/v2/j11.asm /tmp/j11-v2.bin
```

`--cpu=name` is also supported. Unknown profiles and unsupported instructions
are errors; there is no implicit mixed-ISA profile. For example, `sws` and
`gget` share an encoding but are valid in different profiles.

A source can require the selected profile without emitting bytes:

```asm
    cpu ucode
```

This is an assertion against `--cpu`, not a mid-file switch. The v2 entry
source uses it. The read-only predefined constants `__CPU_ORIGINAL__`,
`__CPU_J11__` and `__CPU_UCODE__` are all defined; exactly one equals 1.
Use `if __CPU_UCODE__`, not `ifdef`, to test the selection.

## ISA differences

| Feature | original | j11 | ucode |
|---|---|---|---|
| SWS, SWU, SETP, GETP | Yes | No | No |
| GGET/GSET immediate context | No | 0..31 | 0..63 |
| GGETR/GSETR indexed context | No | Index register low 6 bits | Index register low 6 bits |
| GETF, native byte subtract SUBB | No | Yes | Yes |
| Native MOVL/MOVH | Yes | Yes | No |
| LDI8 | No | No | Yes |
| PC destination | Legacy rules | Legacy rules | MOV, GGET, GGETR only |

`LDI8 Rd, imm8` loads **0..255**, clears the upper byte, and preserves native
NZVC. Its opcode field `instruction[7:3]` is `0x0c`, replacing the old
native MOVL; the destination is in bits 2:0 and the constant in bits 15:8.
It is not a PDP-11 instruction. Removing native MOVL/MOVH does **not** remove
guest MOVB.

GGET/GSET use bits 12:8 in the reference and bits 13:8 in the new engine.
Out-of-range context constants are rejected rather than silently aliasing.
Context words 10, 11 and 15 remain native cause/IRQ/control service ports;
the other words are firmware-owned RAM.

The new engine drops partial-PC writes and ALU/load/GETF-to-PC paths.
Relative branches remain available, and PC can still be read as a source.
A native instruction at byte address A reads PC as A+1, preserving the
firmware call ABI. MOV/GGET/GGETR can explicitly redirect instruction fetch.

The comparison result is registered in the existing PRE_EXEC state before
the PC adder. Ordinary instructions still take six clocks. Variable shifts
and guest-memory waits retain their extra cycles. The bus request stays
stable until completion, and a failed transaction transfers to byte 0002.

For compatibility, `original` and `j11` retain the assembler's legacy
4-bit immediate behavior (16 encodes as 0; negative values are masked).
The new `ucode` profile requires 0..15. SETL/SETH keep their byte-extraction
semantics. The SET macro remains **two words**, including for forward labels;
there is no pass-dependent instruction shrinking. V2 uses explicit LDI8 at
known small constants, so fixed-length far-call/skip macros remain valid.

Guest decode, EA modes, PSW, architectural register banks, FIS, HALT,
processor I/O registers and device semantics remain in firmware. The new
engine does not hard-code additional J-11 instructions or register banks.

## Object files and disassembly

Object-header word at byte offset `0x10` contains the CPU ID in version-2
objects: 0 = original, 1 = j11, 2 = ucode. The `j11` and `ucode` profiles
write version 2 so older tools reject them instead of ignoring CPU metadata.
The `original` profile retains the byte-compatible version-1 format.
New tools read both versions; version-1 reserved fields remain uninterpreted.
Old untagged objects are original; rebuild old J-11 objects with an explicit
profile.

`microlink` rejects mixing profiles, even if an individual input uses only
common instructions. Assemble shared modules separately for each target.
Bounded context/LDI8 operands cannot have relocations; use SETL/SETH for
relocatable addresses.

`microdis --cpu original|j11|ucode file.bin` selects raw-binary decoding.
For objects it reads the CPU tag automatically; an explicitly conflicting
profile is an error. Raw binaries have no metadata: use the matching engine
and profile. Disassembly no longer guesses SWS versus GGET from operands.

## Separate builds

```sh
make -C asm test

# Preserved engine and ROM:
make -C boards j11-ucode
make -C testbench test
make -C testbench j11-core-banks-test j11-nofis-test

# New engine and independent ROM:
make -C boards j11-v2-ucode
make -C testbench ucode-test ucode-core-test
make -C testbench ucode-fis-reference-test
```

Board outputs:

| Profile | Portable image | EBR module | Diamond project |
|---|---|---|---|
| j11 | `j11_ucode.mem` | `j11_urom_ebr.v` | `microcomp-j11.ldf` |
| ucode | `j11_ucode_v2.mem` | `ucode_urom_ebr.v` | `microcomp-ucode.ldf` |

These files are under `boards/hc1200-microcomp/`. The new board wrapper is
`ucode_microcomp.v`; pinout and raw UART/time/FRAM services are shared.
Both ROM paths are generated by `boards/Makefile`. Neither target overwrites
the other's image. The separate `j11-v2-diamond` target is available for
synthesis; it is not needed for Mac simulations.

For simulation with the actual EBR primitive model already copied locally:

```sh
make -C testbench ucode-ebr-test LATTICE_SIM_DIR=/path/to/machxo2/models
```

This uses Icarus and does not launch Diamond or program the FPGA.

## Size and verification

With FIS enabled and the same 3584-word physical memory:

| | Reference j11 | New ucode |
|---|---:|---:|
| Microcode words | 3463 | 3317 |
| Context words | 64 | 64 |
| Free code words | 57 | 203 |

Saving: **146 words / 292 bytes**, from 141 explicit short constants and five
direct high-context accesses. The physical allocation remains seven EBRs.
Diamond 3.14 measured the complete HC1200 board on 2026-08-28:

| | Reference j11 | New ucode |
|---|---:|---:|
| LUT4 / 1280 | 1085 | 964 |
| Slices / 640 | 544 | 483 |
| EBR / 7 | 7 | 7 |
| Registers / 1346 (MAP) | 378 | 379 |
| TRACE maximum internal clock | 34.204 MHz | 41.432 MHz |

Synthesis, MAP, PAR, setup/hold TRACE and JED export pass at the unchanged
26.6 MHz constraint. There are 316 free LUTs and 157 free slices, but no free
EBR. Worst setup is the half-cycle reset-to-UART path: actual slack +6.729 ns,
period-normalized slack +13.458 ns; hold is +0.289 ns. Warning categories and
counts match the reference, including JTAG/GPIO and Synplify diagnostics.
External UART/FRAM timing and physical operation remain unverified. Source
and regenerated image hashes match Mac/Ubuntu; no board was programmed.

Regression covers CPU selection and rejection, object compatibility,
all 256 LDI8 constants, context addressing, legal jumps, native flags,
memory waits/faults, guest instructions, FIS, alternate registers/SP,
HALT, processor I/O and UART/timer behavior. The independent native ALU
test contains 115255 checks. The J-11 no-MMU core suite compares 209
instruction snapshots, including 29 EIS cases.

Verified on the Mac: the 11 existing assembler smoke checks and 17 CPU-profile
tests pass; the preserved CPU/J-11 regression passes; the new engine passes
209/209 core snapshots with both portable RAM and Lattice's EBR model, and
4040/4040 exact-reference FIS cases. EBR checks also exercise all 256 LDI8
values, 1152 context write/read pairs, code integrity, guest instructions,
register banks, HALT and peripherals. The subsequent Diamond build above
also passed; generated reports/JED are ignored build artifacts.

This is the first specialized-engine iteration. A separate word-addressed
microsequencer, CALL/RET, a changed helper ABI and carry-chain instructions
are future changes, not features implemented by the profile switch.

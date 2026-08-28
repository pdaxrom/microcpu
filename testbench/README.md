# Verilog simulators and CPU tests

[Legacy CPU](../README.md) · [Preserved J-11 engine](../docs/fpga-j11.md) ·
[Specialized engine](../docs/ucode-cpu.md) · [Diamond](../docs/diamond.md)

All commands below run from the repository root unless stated otherwise.
These tests run on macOS/Linux without Diamond, an FPGA or physical media.
Icarus is the main regression simulator; Verilator provides compiled
wire-level SD/RT-11 tests. Neither is a substitute for synthesis, place/route,
timing checks or a physical-board test.

## Dependencies and paths

- make, a C compiler, Python 3 and Icarus Verilog (`iverilog` plus `vvp`).
- Verilator and a C++ toolchain for targets ending in `-fast`, the complete
  diagnostic suites and boot-trace tests. These use `--binary --timing`.
- Tcl (`tclsh`) for the static board tests that exercise the Diamond scripts
  with mocked commands; they do not invoke Diamond.
- The sibling `k1801vm1/microasm11` assembler for guest PDP-11 programs.
  The Makefile checks that it exists; it does not build it for you.
- The sibling `k1801vm1/core` and `tests/core_tests.c` for C-reference replay.
- Optional Lattice MachXO2 Verilog models for the explicit `*-ebr-test` targets.
- Your raw RT-11 disk image for RT-11 boot tests; none is distributed here.

The local verified tools are Icarus **12.0** and Verilator **5.050**. These are
tested versions, not a claim that every older release works. Installation and
general tool usage are covered by the official
[Icarus documentation](https://steveicarus.github.io/iverilog/usage/index.html)
and [Verilator installation guide](https://verilator.org/guide/latest/install.html).
An old Verilator without the timing-enabled binary flow is insufficient.

```sh
make -C asm
asm/microasm --list-cpus
iverilog -V
verilator --version
python3 --version

# Build the guest assembler in its own checkout, if not already built.
make -C /Users/sash/Work/PROJECTS/k1801vm1/microasm11

# Override sibling paths when your checkout layout differs.
make -C testbench ucode-core-test \
  ASM11=/absolute/path/k1801vm1/microasm11/microasm11 \
  CORE_DIR=/absolute/path/k1801vm1
```

Default `ASM11` is `../../../PROJECTS/k1801vm1/microasm11/microasm11`,
and `CORE_DIR` is `../../../PROJECTS/k1801vm1`, both relative to
**testbench/**. Prefer absolute override paths. `MICROASM11_DIR` can also
override the directory used to derive `ASM11`. Simulator commands can be
overridden with `IVERILOG`, `VVP` and `VERILATOR`; Python with `PYTHON`.

## Select a CPU and test scope

| Target | CPU / scope | Simulator |
|---|---|---|
| `run-smoke_pass`, `run-isa_alu`, `board-smoke` | Legacy `rtl/cpu.v` | Icarus |
| `test` (also root `make test`) | Legacy native/bootloader/board tests **plus preserved j11** | Icarus |
| `j11-test` | Preserved microengine, guest instructions, FRAM, peripherals, banks, HALT and directed FIS | Icarus |
| `j11-core-banks-test` / `j11-fis-reference-test` | Preserved engine: 209 selected core snapshots / 4040 exact FIS cases | Icarus + C/Python reference |
| `ucode-test` | Specialized native engine + guest suites + no-FIS traps, no disk | Icarus |
| `ucode-core-test` / `ucode-fis-reference-test` | Specialized engine: the same selected core / exhaustive FIS checks | Icarus + C/Python reference |
| `profile-acceptance` | Ordered original + preserved + specialized acceptance, including assembler and preservation checks | Icarus + C/Python reference |
| `profile-acceptance-ebr` | Above plus both microengines' actual vendor EBR models | Icarus + vendor models |

These targets belong to `testbench/Makefile`. **Plain `make -C testbench`
only compiles the original `tb.vvp`; it does not execute a test.** Root
`make test` does not include the specialized `ucode` or SD/RT-11 suites.

### Legacy CPU: quick run and waveform

```sh
make -C testbench run-smoke_pass
make -C testbench run-isa_alu
make -C testbench board-smoke
make -C testbench vcd-isa_alu
```

The last command produces `testbench/build/isa_alu.vcd`, viewable in a VCD
viewer such as GTKWave. `run-NAME` / `vcd-NAME` select
`testbench/programs/NAME.asm`, assembled for the original native ISA.
They do not select guest J-11 programs.

To rerun an already built original test manually, run **inside testbench/**:

```sh
vvp tb.vvp +PROGRAM=build/isa_alu.hex +TIMEOUT=200000 +VCD=build/isa_alu.vcd
```

`+PROGRAM` is required; `+TIMEOUT` and `+VCD` are optional. This VCD option
belongs to the original harness, not every J-11/Verilator testbench.

### Preserved and specialized engines

```sh
make -C testbench j11-test j11-core-banks-test j11-nofis-test
make -C testbench ucode-test ucode-core-test
make -C testbench ucode-fis-reference-test FIS_JOBS=4

# Complete profile comparison, intentionally ordered by the Makefile.
make -C testbench profile-acceptance FIS_JOBS=4
```

`ucode-test` expands to `ucode-native-test`, `ucode-j11-test` and
`ucode-nofis-test`. The `j11` prefix in the latter guest-test names does
not change the selected native engine. Guest tests in `j11_programs/` are
assembled with **microasm11 --cpu dcj-11**; engine firmware uses
**microasm --cpu j11/ucode**. Never interchange these assemblers or native ROMs.

Run these suite commands sequentially, without outer `make -j`: core
fixtures and some generated outputs are shared. Use `FIS_JOBS` for the FIS
runner's own parallelism and `VERILATOR_JOBS` for Verilator compilation.
They change host parallelism, not simulated clock rates.
The preservation check compares nine original/reference RTL and assembly
sources against commit `d4dabf1`; it needs that commit in the local Git history.

### Actual Lattice EBR models

```sh
make -C testbench ucode-ebr-test \
  LATTICE_SIM_DIR=/path/to/diamond/cae_library/simulation/verilog/machxo2
make -C testbench profile-acceptance-ebr FIS_JOBS=4 \
  LATTICE_SIM_DIR=/path/to/diamond/cae_library/simulation/verilog/machxo2
```

The directory must contain `PDPW8KC.v` and its dependencies. On macOS use
a local copy from an installed Diamond; the default path is
`$HOME/.local/lscc/diamond/3.14/cae_library/simulation/verilog/machxo2`.
Normal tests use behavioral memory. EBR targets use the generated initializer
and Lattice primitive models but still run **Icarus**, not Diamond or a
post-route netlist. The complete EBR suites are slower and print case progress.

## SD, RT-11 and diagnostics

These use the specialized `ucode` engine and separate Makefiles:

```sh
# Icarus: wire-level card/FRAM and absent-MMU regression.
make -C testbench -f Makefile.disk disk-test disk-nofis-test
make -C testbench -f Makefile.disk disk-native-isolation-test
make -C testbench -f Makefile.disk disk-image-test disk-no-mmu-test
make -C testbench -f Makefile.disk disk-core-test disk-fis-test FIS_JOBS=4
make -C testbench -f Makefile.disk hc1200-sd-test

# Same seven synthetic cold-boot cases, two independent simulators.
make -C testbench -f Makefile.disk disk-cold-boot-fast VERILATOR_JOBS=4
make -C testbench -f Makefile.disk disk-cold-boot-test

# Native transport diagnostic: Verilator suite / single Icarus smoke.
make -C testbench -f Makefile.diag diag-test
make -C testbench -f Makefile.diag diag-smoke

# NOFIS guest boot trace: Verilator suite.
make -C testbench -f Makefile.boot-trace boot-trace-test
```

`disk-native-isolation-test` is also included in `disk-test`. Its assembled
DCJ11 guest checks 108 vector-4 faults: word reads/writes, instruction fetches,
both byte lanes across private F000..F00F, odd-word ADR priority, and unmapped
FF78..FF7F next to the real DL11. It checks unchanged load destinations and
working DL11 CSRs. Both FIS and NOFIS firmware run on the complete SD/FRAM
adapter; bus assertions reject any extended native-service request, bank
override, SD command or SD/UART pin side effect after guest entry. The same
guest runs in `ucode-test`, and the FIS SD EBR suite includes it too.
See [isolation fix and evidence](../docs/native-service-isolation.md).

Diagnostic suites include a normal run with the real 50-Hz divider and fault
runs with an explicitly accelerated timer. CPU/UART/SPI clocks are unchanged.
See [transport diagnostics](../docs/hc1200-diagnostics.md) and
[boot trace](../docs/hc1200-boot-trace.md) for scenarios and EBR targets.

The full RT-11 scenario, below, retains board divisors and takes about ten
host minutes in the recorded Verilator run; Icarus is substantially slower.
`rt11-bootstrap-test` checks only the first two sectors and entry PC, not a
complete operating-system boot. No generic `SIM=verilator` switch exists:
choose the implemented target for the desired simulator.

## Outputs and failure diagnosis

Generated binaries, listings, memory images and simulation logs live under
`testbench/build/`; they are not source files. `*.asm.log` records assembly
errors and `*.lst` maps microcode labels to addresses. Microcode `*.words`
is a 16-bit image from the production EBR packer; guest/native test `*.hex`
is a byte-addressed image. Do not substitute one format for the other.

A test must print its pass result and exit successfully; a compiled `.vvp`,
a running executable, or a lone RT-11 banner is not a pass. Check the first
`FAIL` / `$fatal`, assembly log or Verilator build log. For a long RT-11 run,
inspect `simulation.log`, `console.log` and `result.json`. Instruction traces
are enabled with `RT11_VERIFY_ARGS='--trace'`, not the original harness's
`+VCD` switch. Copy any logs you need before `make clean`, which removes
`build/` and generated simulation files.

## Original harness details

The original CPU testbench builds assembly programs from `programs/`, loads
them into behavioral 64-KiB memory with `$readmemh`, and exits through the
test-only status register at `$fffe`. The following MMIO is a **test harness**
interface, not the J-11 guest's I/O map.

### Test-only MMIO

- `$fff4..$fff7`: expected read transaction queue
- `$fff8..$fffb`: expected write transaction queue
- `$fffc`: expected UART transmit byte
- `$fffd`: external interrupt trigger; `1` is immediate, values above `1`
  schedule a delayed interrupt
- `$fffe`: test status, `0` means pass and non-zero means fail code
- `$ffff`: character output

The harness also models the board MMIO blocks used by the programs:

- `$ffe0..$ffe1`: UART status/data
- `$ffe8..$ffeb`: GPIO data/direction
- `$fff0..$fff2`: timer counter/status

Bootloader smoke tests assemble `bootloader/bootldr-mcu.asm` and exercise the
banner, `S` save, `G` go, and `L` load command paths through the UART model.

### Legacy board smoke tests

`make -C testbench board-smoke` compiles selected board top-levels with real
board UART/GPIO/timer modules and behavioral stubs for Lattice `OSCH`, `sram`,
and `srampages`.

- `board-mcu-smoke` loads `board_programs/board_uart_smoke.asm` into the
  `hc1200-mcu` zero-page SRAM and verifies a byte sent through the real UART.
- `board-mcu-bootload-rx` boots `bootloader/bootldr-mcu.asm` on the
  `hc1200-mcu` top-level, drives the board UART RX line with a load command,
  checks the written SRAM bytes, then jumps to the loaded payload.
- `board-microcomp-memmap` loads `board_programs/microcomp_memmap.asm` into the
  `hc1200-microcomp` zero-page SRAM and verifies memory page boundaries,
  memory-map interrupts for both remap slots, dirty flags, and UART pass byte.

## Preserved J-11 instruction coverage

`j11-test` assembles the microengine firmware with `microasm` and guest
  PDP-11 programs under `j11_programs/` with `microasm11 --cpu dcj-11`. It
  covers FRAM transactions, the HC1200 I/O overlay and DL11, guest fetch,
  condition-code operations, all PDP-11 conditional branches, all addressing
  modes for `MOV` and `MOVB`, `CMP/CMPB`, `BIT/BITB`, `BIC/BICB`, `BIS/BISB`,
  `XOR`, `ADD`, `SUB`, `CLR/CLRB`, `COM/COMB`, `INC/INCB`, `DEC/DECB`, `NEG/NEGB`,
  `ADC/ADCB`, `SBC/SBCB`, `ROR/RORB`, `ROL/ROLB`, `ASR/ASRB`, `ASL/ASLB`,
  `TST/TSTB`, `SWAB`, `SXT`, `MFPS`, `MTPS`, `MFPT`, `SPL`, `WAIT`, `RESET`,
  `RTT`, `MARK`, `TSTSET`, `WRTLCK`, `MUL`, `DIV`, `ASH`, `ASHC`, `SOB`, the
  software-trap group, both R0..R5 sets, HALT/Proceed, and an assembled guest
  write to the physical DL11 UART. The
  double-operand test includes borrow, carry,
  signed-overflow, byte-width, and
  memory-destination/autoincrement cases. `bic_bis.asm` additionally verifies
  carry preservation, byte-register high-byte preservation, odd byte addresses,
  and byte/word autoincrement and autodecrement. `ea_timing.asm` verifies
  DCJ11 late register-source sampling after destination EA side effects for
  `MOV/MOVB`, `CMP/CMPB`, `BIT/BITB`, `ADD`, `SUB`, and PC-relative extensions. The
  `control_flow.asm` test covers `JMP`, `JSR`, and `RTS`, including DCJ11
  same-register EA timing, `JSR PC`, `RTS PC`, and the special `RTS SP` order.
  `control_traps.asm` verifies that register-direct `JSR` enters vector `010`
  without modifying the link register. The reserved-instruction test enters
  vector `010`, builds a guest stack frame in FRAM, runs a RAM handler, and
  returns via `RTI`; no RAM instruction emulator is installed. Separate
  assembled tests cover
  odd-word bus error vector `004`, `BPT/IOT/EMT/TRAP`, `SOB` flag preservation,
  `COM/COMB` byte and word EA behavior, `INC/INCB` and `DEC/DECB` boundary
  flags and all memory EA modes. `neg_adc_sbc.asm` verifies replacement of all
  four NZVC flags, carry-in zero and one, arithmetic boundaries, byte-register
  high-byte preservation, and memory side effects. `shift_rotate.asm` checks
  incoming and outgoing carry, `V = N xor C`, arithmetic sign fill, byte
  register preservation, and word/byte memory destinations. Tests also cover an
  externally supplied interrupt vector `060`. `irq_priority.asm` verifies that
  BR4 is deferred at PSW
  priority 4 while BR5 preempts it, and that a masked request remains latched.
  `system.asm` checks that `MFPT` preserves NZVC, `SPL` replaces only priority,
  and `WAIT` holds execution until a real BR4 request enters vector `060` and
  returns through `RTI`.
  `reset_rtt.asm` checks RESET flag preservation, the reset pulse and pending
  interrupt clearing, plus RTT trace deferral. `trace_return.asm` verifies the
  stacked PC and executed-instruction count: RTI restoring T traces before the
  next instruction, whereas RTT allows exactly one instruction first.
  `mark_lock.asm` covers `MARK 2`, lock operations and register-direct lock
  traps; `mark_edges.asm` adds NN=0 and NN=63 (`MARK 077`), checking R5, SP,
  control flow and unchanged NZVC. `lock_edges.asm` checks already-locked
  positive/negative words, zero/negative WRTLCK results with both carry states,
  word autodecrement and TSTSET's R0/address-register overlap.
  `mul.asm`, `div.asm`, `ash.asm` and `ashc.asm` cover signed arithmetic,
  shifts, register-pair behavior and boundary flags. `previous_space.asm`
  exercises the existing simplified unified-space moves, and `privileged.asm`
  checks PSW restrictions. `sp_banks.asm` initializes USP/SSP through MxPI,
  checks K/U/S transitions, BPT stack selection, RTI/RTT and previous-mode SP.
  The active no-MMU V1
  scope and deferred work are recorded in [TODO.md](../TODO.md).

## J-11 C-core fixture replay (Mac, no Diamond)

```sh
make -C testbench j11-core-banks-test
```

`CORE_DIR` defaults to the sibling `k1801vm1` repository. `core_reference.c`
includes its existing `tests/core_tests.c`, runs only explicitly selected DCJ11
functions with `ENABLE_MMU=0`, and exports before/after instruction snapshots.
The original C assertions still run. `run_core_reference.py` disassembles each
input instruction, writes an assembly source under `build/core_reference/`,
assembles it with `microasm11`, and requires an exact byte round-trip before
replaying it on `j11_microengine`. Intentionally illegal JMP/JSR register-direct
encodings use documented `dw` directives, because the assembler rejects them.
The script normalizes upstream disassembler spelling for MARK and MFPI/MFPD.

Replay checks R0..R7, all PSW bits, every RAM byte and valid inactive SP/R0..R5 banks
at the next instruction boundary, after any synchronous trace/trap. It uses
a flat, deterministic RAM bus; `j11-test` separately covers actual SPI FRAM
and the HC1200 guest bus. Failed cases keep their individual inputs/expectations.

Current coverage: 209 instruction snapshots, including 29 EIS cases, CPU I/O,
SP transitions and the existing general-register-set banking test. This is
**not** the complete upstream test suite: VM1/VM2, FP11/FIS, MMU/split I/D,
and C backend-only tests are not selected. Console HALT is checked against the
DEC manual, not the C `handle_halt` placeholder.
One MTPS subcase injects the C-only `fTrap` state; its C assertions run but its
RTL replay is explicitly skipped. Uninitialized C-model SP banks are not
compared until the C fixture marks them valid. `j11-core-test` runs the base
selection without the explicit bank-transition cases/checks.

The C fixture lazily clones SP banks at its first mode switch (after a frame
pop for RTI/RTT), and R0..R5 at its first RS switch. Replay explicitly seeds
that latent state without changing the C reference. This is not a hardware
reset requirement: independent assembly tests verify zeroed alternate state.

`register_sets.asm` runs through SPI FRAM in `j11-cpu-io-test`. The separate
`make -C testbench j11-halt-test` runs `halt_console.asm` with a testbench
driver for the private microcode console mailbox, and `halt_privileged.asm`
through SPI FRAM. It covers saved PC/PSW/banks, no bus/reset activity during
HALT, pending IRQs, Proceed, held-request single-step, user WAIT, TRACE and
illegal HALT in S/U with either RS. It adds no guest I/O address or board pin.
The same programs run in `j11-ebr-test` against Lattice's actual EBR model.

### Shared microcode/context memory

`make -C testbench j11-context-test` assembles
`ucode/j11_context_memory.asm` with the native `microasm`. It checks all
ordinary context indexes with distinct patterns, reset clearing, high-index
masking, overlapping source/index registers and native PC reads/writes. Its
last instruction is immediately before the reserved 64-word context region.
Two full runs plus an aborted-store reset verify 35,808 instructions at the
unchanged six clocks per instruction. No context is deposited by this test.

`j11-ebr-test` runs that same program through a separate, generated EBR test
image, without overwriting production microcode. The primitive-port test
checks all 3584 words, 1152 context write/read pairs, simultaneous code reads
and context writes, independent enables, reset write suppression and unchanged
code. The production guest/core suites then run against the production image.
`test_urom_ebr.py` verifies both output formats and rejects code that crosses
into the last 64 words (including the one-word-over boundary).

`include/j11_context_probe.vh` observes actual behavioral/vendor RAM, rather
than keeping a shadow context in the engine. Its only deposits are the existing
C-fixture seeding and private HALT/Proceed stimulus. Guest instruction and
peripheral semantics continue to be tested by `microasm11` programs.

## RT-11 boot from a raw SD image

```sh
make -C testbench -f Makefile.disk rt11-boot-fast
make -C testbench -f Makefile.disk rt11-bootstrap-test
make -C testbench -f Makefile.disk hc1200-sd-test
make -C testbench -f Makefile.disk disk-cold-boot-fast
make -C testbench -f Makefile.disk disk-cold-boot-test # independent Icarus version
make -C testbench -f Makefile.disk disk-cold-boot-ebr-test LATTICE_SIM_DIR=/path/to/machxo2/models
```

The full test uses Verilator and the same SPI FRAM/SD/UART RTL as the board.
FRAM starts empty: the production microcode reads the two boot sectors, sets
the RH0 register ABI and enters the disk code. The shorter independent Icarus
test checks all 1024 loaded bytes and entry into RT-11 code.
`RT11_IMAGE` defaults to the sibling
`k1801vm1/lsi11/disks/rt11v503.dsk`; no disk image is distributed here. The input
is read-only, with a volatile sector overlay for guest writes, and the runner
checks its SHA-256 before and after simulation. The full console scenario
requires `SHOW CONFIGURATION`, the `RT11FB.SYS` directory entry, and a new
prompt after each command. See [RT-11 bring-up](../docs/rt11-boot.md) for logs,
limits, the no-MMU probe correction, SD wiring and physical-board follow-up.

`tb_sd_cold_boot` uses the actual SD board top, including its initialized reset
synchronizer, with `res=1` from time zero. Its synthetic disk boot block is
assembled from `j11_programs/sd_cold_boot.asm` by **microasm11** and is loaded
only into the SD model, never FRAM. Seven scenarios cover empty/stale FRAM,
absent card, first/second-sector failure, wrong OCR and wrong CMD8 echo.
Each failure must stop before any guest instruction; fixing the card plus
board reset must boot successfully. Guest RESET must not reread the disk or
clear guest RAM. Two WAIT/vector-100 interrupts and 532000-clock tick periods
verify the nominal 50-Hz source, including continuity across guest RESET.
The real-EBR target uses the board's generated autoboot ROM, not a diagnostic
image with the entry path bypassed.

`hc1200-sd-test` prepares the main board's SD ROM using the ordinary
`boards/Makefile`, then checks the default LDF source set, independent legacy
project, UART/SD pin locations, identical portable/EBR images and the new
build script's timing/export guards (with mocked Diamond commands).
It boots `sd_cold_boot_uart.asm` from the SD model and checks an actual board
pin exchange: FPGA `tx` sends `'U'`, FPGA `rx` receives `'Z'`, 115200 8N1.
The UART sites are `rx=PT15D`, `tx=PT17D`, unchanged from `microcomp.lpf`.

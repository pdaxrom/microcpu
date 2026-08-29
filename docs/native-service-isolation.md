# Native-service isolation fix (2026-08-29)

## Defect and minimal fix

The `a985039` SD-boot firmware filtered guest addresses with
`(address & 0xFFF8) == 0xF000`. This protected raw UART/time services but
missed the later SD services F008 (SPI byte), F00A (SPI control) and F00C
(FRAM bank override). Guest accesses fell through `cpu_io_decode` to
`memory_raw` and the real SD bus adapter. The earlier handoff incorrectly
implied that the full private window was already protected.

`ucode/v2/j11_memory.asm` now rejects the entire **F000..F00F** range before
raw transactions, for reads, writes, bytes and instruction fetches. Odd-word
alignment is still checked first. A separate FFF8 mask preserves the exact
DL11 range FF70..FF77: simply widening the shared mask would incorrectly
alias FF78..FF7F to the console.

This is an **ASM-only functional change**, adding three native words:
**3504 code + 64 context + 16 free = 3584 words** for SD autoboot with FIS.
No FIS removal, uROM expansion, native ISA change, RTL logic change or pin
change is needed. The board-top comment now points to the existing physical
pinout acceptance instead of calling the pinout unverified. Preserved
`original` / `j11` profiles are unchanged.

## Reproducer and regression

`testbench/j11_programs/native_isolation.asm` is assembled with
`microasm11 --cpu dcj-11`. On the old firmware the full-bus test stops at:

```text
Guest reached private SD service: address=f008 write=0 byte=0 PC=001430 uPC=1078
```

The fixed firmware passes **108 guest vector-4 checks** per run:

- Eight private aligned addresses, each with word read/write/fetch and both
  byte-lane reads/writes: 56 TMO faults.
- Eight private odd addresses, each with word read/write/fetch: 24 ADR faults,
  preserving alignment priority (CPUERR.ADR = octal 0100).
- Four aligned words immediately above DL11, with the same seven accesses:
  28 TMO faults, ensuring the console decode did not grow.
- Faulting reads leave the destination unchanged; valid DL11 CSR byte/word
  accesses still work without transmitting a character.

The SD testbench permits native reset's legitimate service initialization,
then asserts no F008..F00F bus request, no FRAM bank override, no SD command
and no SD/UART pin side effects during the guest probes. Existing disk tests
separately exercise legitimate microcode service accesses for real I/O.

```sh
make -C testbench -f Makefile.disk disk-native-isolation-test
make -C testbench -f Makefile.disk disk-test disk-nofis-test
make -C testbench ucode-test
```

Initial full-bus Icarus results: FIS **2,517,607 clocks**, NOFIS
**2,509,942 clocks**; both pass. The test is included in `disk-test`,
`ucode-test` and `disk-ebr-test`. The preserved-profile checker still reports
all nine original/reference files byte-identical to `d4dabf1`.

## Mac qualification

All commands below exited zero; outputs are under `testbench/build/`:

- `disk-test`, `disk-nofis-test`: 11 disk scenarios each, plus native-service
  isolation and the SPI-byte service tests.
- `disk-no-mmu-test`: all 600 absent-MMU probes and processor-register tests.
- `disk-core-test`: **209/209 snapshots**, including 29 EIS cases.
- `ucode-test`: native ISA, guest ISA/EA, DL11/LTC, RS/SP/HALT, CPU errors,
  isolation, directed/fault FIS and unavailable-FIS traps.
- `hc1200-sd-test`: seven static project checks, real board UART TX/RX,
  guest RESET and two 50-Hz interrupts; **2,700,271 clocks**.
- `disk-cold-boot-fast`: all seven power-on/error/recovery scenarios.
- `disk-fis-test`: **4040/4040 exact-reference cases**.
- `disk-ebr-test`: SD scenarios 0/7/10, all 108 isolation faults and directed
  FIS with actual MachXO2 EBR simulation models.

Logs: `native-isolation-regression.log`, `native-isolation-ucode.log`,
`native-isolation-fis.log`, `native-isolation-ebr.log`.

The **full RT-11 boot** with FIS passed all **8/8 runner checks**, including
SHOW CONFIGURATION and DIRECTORY followed by fresh prompts. It reports
PDP 11/73A, 56KB, EIS, FIS and the 50-cycle clock; `RT11FB.SYS` occupies
103 blocks, with 51455 free. Verilator: **1,614,712,535 clocks**, **599.582 s**,
232 sector reads, 6 simulated writes, 5 dirty overlay sectors, 43/43 RX bytes.
Logs and `result.json`: `testbench/build/rt11-native-isolation/`.

The original `rt11v503.dsk` SHA-256 before and after is unchanged:
`e769228f2e1262220297bfa98b8f2841688849ab4c49ad9cd48d0d73d0a99553`.
The board ROM is byte-identical to the tested autoboot ROM:

| Artifact | SHA-256 |
|---|---|
| `j11_sd.mem` | `c17d85c723ce4ed64bb996dc860ea4e6141f708b800f190fc2f308685ccef7af` |
| `sd_urom_ebr.v` | `0a9efa247dee97e90e6d2c864c51fbdff942f3457ccfd56b4e1f26b7ac60ecd5` |

## Hardware qualification

Source **45a1b6859922874575888f7346c85b1c7d01dd5a** passed the full isolated
Diamond **3.14.0.75.2** / Synplify **V-2023.09L-2 Build 349R** flow. Resources
remain 1095 LUT4, 548 slices, 431 registers and 7 EBRs. TRACE maximum is
37.627 MHz at the 26.6-MHz constraint; setup/hold errors, cumulative negative
slack and unrouted connections are zero.

JED **60FA**, SHA-256
`d878e1927fa3996499b4ae391df12fa6897f8ed70d1d33fe52fa96bce7206879`, passed
`FLASH Verify ID` and **FLASH Erase,Program,Verify** on the HC1200. Programming
exited zero in 20 seconds with 940-ms erase, using FT2232 A / FTUSB-0 at
200 kHz. UART B and the user's open terminal were left connected.
Artifacts and actual XCF/logs are on both hosts under
`boards/hc1200-microcomp/impl1-sdboot/native-isolation-45a1b68/`.

After programming, the user confirmed the RT-11 boot over the physical UART
and captured `SHOW CONFIGURATION` plus `.DIR *.OBJ`. The new JED boots from DM0 as RT-11FB
V05.03 and reports PDP 11/73A, 56KB, Floating Point Microcode, EIS, FIS,
Cache Memory and the 50 Cycle System Clock. This is hardware boot evidence
for source 45a1b68 / JED 60FA. The physical directory lists four OBJ files,
78 blocks total and 51455 free blocks. Detailed sector statistics remain
simulation evidence.
The exact previous programmed JED remains archived under
`impl1-sdboot/kdj11a-a985039/`; do not overwrite that recovery copy.

See [versioned Diamond/hardware acceptance](hc1200-sd-diamond.md),
[RT-11 test scope](rt11-boot.md), and [session handoff](SESSION-HANDOFF.md).

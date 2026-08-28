# HC1200 J-11 SD boot trace (temporarily no FIS)

This image diagnoses the **real SD -> FRAM cache -> guest RAM -> J-11** boot
path. It uses the existing RK611 microcode, not an independent replacement
bootstrap. Only this build defines `J11_BOOT_TRACE` and `J11_DISABLE_FIS`;
normal `make -C boards/hc1200-microcomp` still builds J-11 with FIS.
EIS, register/SP banks, HALT, DL11, the 50-Hz clock and disk writes remain.

No synthesizable RTL, pin assignment, pull mode, oscillator or UART divisor
changes. The separate Diamond project uses the same `ucode_sd_microcomp`
top, `sd.lpf` and `j11.sty`; only the EBR contents differ. Code and diagnostic
text are assembly in `ucode/diagnostics/boot_trace.asm`, with conditional
hooks in `ucode/v2` and `ucode/experimental/rh11_sd.asm`.

The trace occupies **3439 code words + 64 context words** in the existing
3584-word uROM, leaving 81 words unused. FIS was removed only to free code
space for this diagnostic image. All generated files remain untracked.

## Build and select the correct JED

Portable image preparation:

```sh
make -C boards/hc1200-microcomp boot-trace
```

Full Ubuntu build, including placement/routing and setup/hold checks:

```sh
make -C boards/hc1200-microcomp boot-trace-diamond \
  DIAMOND_HOME=/home/sash/.local/lscc/diamond/3.14
```

For the GUI, open `boards/hc1200-microcomp/microcomp-boot-trace.ldf`, not
the normal project or the standalone SD/FRAM diagnostic project. Select
top `ucode_sd_microcomp`; the implementation directory is `impl1-boot-trace`.

Output:

```text
boards/hc1200-microcomp/impl1-boot-trace/microcomp-boot-trace_impl1.jed
```

Select this file explicitly in Programmer. Build targets do **not** program
the board. UART remains **115200 8N1, no flow control** (TX PT17D/pin 23,
RX PT15D/pin 25); SD/FRAM connections are unchanged.

Unlike the standalone `microcomp-diag` firmware, this is a real OS boot:
**FRAM is overwritten by boot/DMA and RT-11 can write the physical SD**.
Back up valuable disk contents before hardware tests. Simulation opens the
source image read-only and redirects all writes into the card's RAM overlay.

## What to capture

Open the terminal before reset, then capture everything from:

```text
J11 TRACE NOFIS
```

The banner appears before any FRAM or SD transaction and does not depend on
either external memory. A healthy boot then shows `C`, `R`, `V`, `D`, `G`
records and ultimately RT-11 output. No terminal key is needed to boot.

Each record has the same field order. **Every numeric field is hexadecimal**,
including PC, SP, PSW, command numbers and disk registers:

```text
TAG CMD LBAhi LBAlo OFF CS1 WC BA ER SP PC PS IR CAUSE V0 V1
```

For example, at completion of the initial two-sector transfer:

```text
D 0011 0000 0001 0200 0090 0000 0400 0000 0000 0000 0000 0000 0000 0090 0001
```

The important fields here are `WC=0000`, `BA=0400` (1024 bytes transferred),
`ER=0000`, last `LBA=1`. `V0/V1` are raw native scratch values and normally
have meaning only for the specific record types below. The `D` line precedes
setting the guest boot registers; `G` then shows `SP=0400`, `PC=0000`, `PS=0004`.

| Tag | Meaning / useful fields |
|---|---|
| `C` | SD command response: `CMD & 00FF` is the command number, `V0` is R1. `0037` means CMD55, `0029` means ACMD41, `003A` means CMD58, `0011` means CMD17. |
| `R` | About to read `LBAhi:LBAlo`. CMD still describes the preceding command until the next `C`. |
| `V` | All 512 SD bytes passed CRC16 and every word written into the bank-1 FRAM cache passed immediate readback. `V0=received CRC`, `V1=computed CRC`. This precedes copying the cache to guest RAM. |
| `D` | An RH command finished. Check `CS1`, `WC`, `BA`, `ER`; `D` alone is not a success indicator. For reads, each word copied from cache to guest FRAM was read back and compared. |
| `G` | Guest state, once at bootstrap handoff and roughly once per second at instruction/WAIT boundaries until guest console output starts. Also repeats while stopped. |
| `E` | SD transport failure: last CMD/LBA and raw `V0` at the error site (R1, R7/OCR byte, token or timeout delta). CS1/ER are printed **before** committing the RH error bits. |
| `S` | Bootstrap failed after RH cleanup; cause 5, final CS1/WC/BA/ER. No stale/partial guest code executes. |
| `X` | CRC mismatch; `V0=received`, `V1=computed`. Bad sector is not DMA'd into guest RAM. Followed by `E`, and `S` if booting. |
| `K` | SD -> FRAM cache write/read mismatch: `OFF` byte offset, `V0=expected`, `V1=readback`, cause 6. |
| `M` | Cache -> guest FRAM mismatch: `BA` guest byte address, `OFF` cache offset, `V0=expected`, `V1=readback`, cause 6. |

Cause 3 means guest HALT/console stop, 4 means double-abort stop, 5 means
failed SD bootstrap, and 6 is the private fatal FRAM-readback error. Causes
1/2 are bus/reserved-instruction traps, not necessarily fatal OS failures.

`CMD` bit 15 is private trace state: normal progress is suppressed after the
first guest write to the DL11 transmitter. Trace output is fully drained
before guest execution resumes, so the first guest byte is not dropped.
RX is never consumed by diagnostics. This keeps the RT-11 prompt usable;
errors and stopped-state reports remain visible. Board reset starts a new
capture. These diagnostics are not an ODT implementation.

Readback checks cover the two boot-transfer paths, not the whole 128-KiB
FRAM address space or all possible alias/timing faults. Likewise, a CRC PASS
does not prove that a sector belongs to the intended OS image.

## Verification

### Physical-board result (2026-08-28)

The `J11 TRACE NOFIS` JED booted the real HC1200 from the same RT-11 V05.03
SD image. The captured trace contained 86 `R` and 86 matching `V` records,
with no `E`, `S`, `X`, `K`, or `M` records. All traced sector CRC pairs
matched and all RH completion error fields were zero. RT-11 then executed
`SHOW CONFIGURATION`, `DIRECTORY`, and `SHOW ALL`; DM0 was resident at octal CSR
`177440`, vector `210`, with 56 KiB guest RAM and the 50-Hz clock reported.

This confirms the physical SD -> FRAM cache -> guest FRAM -> CPU path used by
the real boot. It does not identify the cause of the earlier silent run by
itself, because this image also adds diagnostic UART output and readback work.

### Reproduce simulation

```sh
make -C testbench -f Makefile.boot-trace boot-trace-test
make -C testbench -f Makefile.boot-trace boot-trace-ebr-test \
  LATTICE_SIM_DIR=/path/to/diamond/machxo2/models
make -C testbench -f Makefile.boot-trace boot-trace-rt11
```

The smoke suite uses the actual board top and physical serial pins. The
PDP-11 boot fixture is assembled by `microasm11` and placed only on the SD
model; FRAM starts with hostile stale contents. It checks the boot register
ABI, both loaded sectors, guest RESET/WAIT/UART, silence during the guest RX
wait, and repeating HALT reports. The normal run uses the real 50-Hz divisor.

Faults cover absent SD, second-sector error, wrong CRC, protected cache or
guest RAM writes, absent token, bad CMD8/OCR, stuck ACMD41 and read-error
token. Fault runs accelerate only the tick timer, not CPU/UART/SPI timing.
They verify that failed boot never fetches a guest instruction, corrupt-CRC
data is not DMA'd, buses are released and stop reports continue.
Two additional runtime tests boot an assembled guest that prints a byte and
checks that `FADD` enters reserved-instruction vector 010, then issues disk
I/O. A rejected write data token (with bank 1 still active)
and a bad read CRC must still produce error records after progress has been
suppressed, return an RH error to the guest and leave the buses released.

The RT-11 harness waits for this fixture's final `.SET SL ON` startup line
before treating a standalone dot as an interactive prompt. A dot before a
slow startup-file read is not sufficient evidence that KMON is ready.

### Simulation result (2026-08-28)

- All 13 board-level scenarios passed, including the real-50-Hz normal run,
  both runtime errors and the functional `FADD` -> vector 010 check.
- Four image/project/export-guard tests passed; the standalone diagnostic's
  three existing checks also passed after sharing the test helpers.
- Two four-state Icarus runs with Lattice `PDPW8KC`/`DP8KC` models passed:
  second-sector failure and guest-FRAM DMA mismatch, including UART reports.
- The existing board UART/RESET/50-Hz test, SPI-byte tests and all 11 RK611/SD
  scenarios passed. The rebuilt normal FIS-enabled MEM/EBR hashes are unchanged.
- Full RT-11 V5.03 boot, `SHOW CONFIGURATION`, `DIRECTORY SY:RT11FB.SYS` and
  return to the prompt passed: 1,725,336,706 native clocks, 232 SD reads,
  6 simulated writes, 5 overlay sectors. Host runtime was 614.653 seconds;
  the **whole scripted sequence**, not the first banner, is about 64.9 seconds
  at 26.6 MHz. Logs: `testbench/build/rt11-boot-trace/`.
- Input image SHA256 before/after is identical:
  `e769228f2e1262220297bfa98b8f2841688849ab4c49ad9cd48d0d73d0a99553`.

This RT-11 image still prints `Floating Point Microcode` in its configuration
report. That string is its description of a J-11 without the optional FPA
accelerator: MAINT[8] is clear. It is not a FIS indicator. The functional
`FADD`/vector-010 check verifies that FIS is disabled in this diagnostic build.

### Diamond result (2026-08-28)

Fresh isolated build on Ubuntu with Diamond 3.14, `LCMXO2-1200HC-4SG32C`:
1095/1280 LUT4, 548/640 slices, 431 registers, 7/7 EBR, 17 PIO + JTAGENB.
All connections routed. At the 26.600-MHz constraint, setup/hold cumulative
negative slack is zero; reported internal maximum is 37.627 MHz and minimum
hold slack is +0.289 ns. This is synthesis/P&R evidence, not a hardware test.
BITGEN reports zero errors and one WID-pattern warning for `CFG_EBRUFM`;
this build uses ordinary `CFG`, with zero initialized UFM pages. The existing
preloaded-EBR wake-up advisory and configuration-port warning also remain;
configuration/JTAG settings have not been changed.

Generated MEM and EBR contents match the Mac assembly byte for byte:

```text
MEM SHA256 a5b3ad539eb717bd71be7a3af767fcfdf0527ae3fd2f413d1489a3d1e3a6a86f
EBR SHA256 ccdc46d3d0eb10fd7c7889783c93e24c7fb53f072c2b26bfa05a17758e892c60
JED SHA256 f95b3b83295aa8368708a927bf7fb9f2f0a5578c98145ec95d696b709ebdc7b4
```

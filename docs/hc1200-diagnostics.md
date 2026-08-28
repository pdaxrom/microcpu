# HC1200 UART / SD / FRAM diagnostic uROM

If these transport tests pass but normal RT-11 boot remains silent, use the
separate [J-11 SD boot trace](hc1200-boot-trace.md) to follow the actual
bootstrap, sector CRC/readback checks and guest execution.

This is **native microcode**, assembled from `ucode/diagnostics/sd_fram.asm`
with `microasm --cpu ucode`. It does not run a PDP-11 guest or depend on a
bootable SD image, external FRAM contents, or a FRAM-resident stack.

The separate `microcomp-diag.ldf` project uses the **same board top, CPU,
UART, SD/FRAM services, clock, strategy and `sd.lpf`** as `microcomp.ldf`.
Only the generated uROM contents change. The normal J-11 images, project,
pin locations and pull modes are not replaced. Depth stays 3584 words with
64 words of internal context. Generated BIN/MEM/EBR/listing files are ignored.

## Build and program

On either Mac or Linux, generate the image (no Diamond needed):

```sh
make -C boards/hc1200-microcomp diag
```

On Ubuntu, build the separate JED:

```sh
make -C boards/hc1200-microcomp diag-diamond \
  DIAMOND_HOME=/home/sash/.local/lscc/diamond/3.14
```

Alternatively, after `make ... diag`, open
`boards/hc1200-microcomp/microcomp-diag.ldf` in Diamond. Top must be
`ucode_sd_microcomp`, implementation directory `impl1-diag`. Do not select
the generated EBR module as the top.

Output: `boards/hc1200-microcomp/impl1-diag/microcomp-diag_impl1.jed`.
The build checks synthesis, mapping, routing and timing before JED export.
It **never programs hardware**. Select this JED explicitly in Programmer;
the old normal-project XCF still points at the normal J-11 JED.

## Terminal and operation

Use **115200 baud, 8 data bits, no parity, 1 stop bit, no flow control**,
3.3-V TTL UART, with common GND. Board TX is **PT17D / pin 23**, RX is
**PT15D / pin 25**. Adapter RX goes to board TX; adapter TX goes to board RX.
On the repository's schematic these are JP1-15 and JP1-13 respectively.

The exported PAD report retains these SPI connections (site / QFN pin):

| Signal | SD | FRAM |
|---|---|---|
| CS_n | PL9B / 5 | PB4C / 8 |
| MOSI | PR5C / 21 | PB20D / 17 |
| SCLK | PT12D / 27 | PB6C / 9 |
| MISO | PT12C / 28 | PB6D / 10 |

At configuration or board reset, before touching SD or FRAM, TX prints:

```text
HC1200 DIAG 115200 8N1
FRAM READ: ...
SD CMD0 R1=01
SD CMD8 R1=01
R7=000001AA
SD ACMD41 R1=00
SD CMD58 R1=00
OCR=...
SD SLOW R1=00
TOKEN=FE
CRC=xxxx/xxxx PASS
DATA=... first 16 bytes of LBA 0 ...
SD FAST R1=00
TOKEN=FE
CRC=xxxx/xxxx PASS
DATA=...
ALIVE R=read W=FRAM-write
```

`ALIVE` repeats every second, so opening the terminal after startup does
not lose all output. Neither a missing card nor a failed FRAM test prevents
the menu. If absolutely nothing is visible, first check the selected JED,
board reset/power, TX waveform and UART connection/settings; this banner
does not depend on a working SD card or FRAM.

- **R/r:** repeat the read-only diagnostics, including a new banner and SD
  initialization. Card insertion followed by R is supported.
- **W/w:** run the FRAM write/read test described below.
- Other characters are echoed, checking UART RX as well as TX. No Enter is
  needed for commands.

## SD: strictly read-only

Commands are CMD0, CMD8, CMD55/ACMD41, CMD58 and CMD17 only. Nothing writes,
erases or formats the card. An SDHC/SDXC card with 512-byte block addressing
is required, matching the current autoboot firmware. Unsupported CMD8 or
OCR/CCS values are printed before failure; SDSC/MMC fallback is not added.

The same physical sector **LBA 0** is read at slow (~195.6 kHz) and fast
(6.65 MHz) SPI. `CRC=calculated/received` must match; CRC16 follows the
[SD Association specification](https://www.sdcard.org/cms/wp-content/themes/sdcard-org/dl.php?f=Part1_Physical_Layer_Simplified_Specification_Ver6.00.pdf)
(initial zero, polynomial 0x1021). Printing data is independent of FRAM:
the 16-byte preview is kept in internal context RAM.

`SD FAIL stage=xx` uses a **hexadecimal command number**: `00` = CMD0,
`08` = CMD8/R7, `29` = ACMD41, `3A` = CMD58/OCR, `11` = CMD17/token/CRC.
Response polling and initialization are bounded. The card is deselected on
failure and the terminal returns to the menu. A slow PASS followed by a fast
failure points toward a speed-dependent link issue, not a missing filesystem.
Both CRC checks passing does not prove that RT-11 is installed at the expected
offset or that the image itself is bootable.

## FRAM: read-only until W

The initial eight-word dump reads physical **hex** `00200..00207` followed
by `10200..10207`. This is not a presence test: an all-zero or all-FF dump
alone cannot distinguish stored contents from a disconnected MISO line.

W saves these **16 bytes total** into internal context RAM, writes four
word-pattern passes (0000/FFFF/55AA/AA55 XOR word index), checks for address
and bank aliasing, tests both byte lanes with A5/5A, then restores the saved
words and checks them. All other FRAM locations are left untouched. This
is a small transport/bank/byte-lane smoke test, not a full 128-KiB memory test.

The first mismatch reports `FRAM BAD i=xx E=expected G=received`; index 0..3
is bank 0, 4..7 is bank 1. `FRAM R/W` and `FRAM RESTORE` have separate PASS/
FAIL results. A failing test still attempts restoration before returning.

**Do not interrupt power/reset during W.** FRAM is nonvolatile: interrupted
restoration can leave test patterns behind. Saving/restoring over an already
faulty SPI link cannot guarantee preservation; back up valuable contents
before explicitly requesting W. Default power-on/R never writes FRAM.

## Simulation

```sh
make -C testbench -f Makefile.diag diag-test
make -C testbench -f Makefile.diag diag-ebr-test LATTICE_SIM_DIR=/path/to/machxo2
```

The bench uses the real board top and decodes its TX pin at the actual UART
divisor. It sends echo/R/W commands through RX, verifies no FRAM write before
W, prohibits SD writes, and compares all 128 KiB of FRAM after restoration.
The normal case uses the real 50-Hz timer; the fault suite and exact-EBR
test accelerate only the timer, retaining CPU/UART/SPI timing.

Fault cases cover absent SD with insertion/retry, bad CMD8 echo, unsupported
OCR, corrupt CRC, error token, stuck initialization, missing data token,
absent FRAM, write-protected FRAM, aliased FRAM banks and a fast-only CRC
error. The SD model also checks the published 512 x FF -> CRC 7FA1 vector.
These are simulated tests; hardware operation must be checked with the
diagnostic JED on the user's board.

## Verified build: 2026-08-28

- Diagnostic code: **944 words**, plus 64 reserved context words, in the
  unchanged 3584-word image.
- 13 Verilator runs passed: normal operation with the real timer plus all
  12 normal/fault scenarios with the accelerated timer. UART output,
  one-second heartbeat, RX echo, card insertion/R retry, W gating and FRAM
  restoration were checked at the pins, not by bypassing firmware.
- The same generated EBR image passed the normal test in Icarus using
  Lattice's PDPW8KC models (3,342,274 board clocks with accelerated timer).
- Project/ROM/export tests: 3 passed. Existing board project tests: 7 passed.
  Existing SD cold boot/UART round trip, SPI-byte service and all 11 RK611/SD
  scenarios passed after the behavioral-model changes.
- A clean source copy in `/tmp/microcpu-sd-fram-diag.pCO52A` on Ubuntu passed
  Synplify, Translate, MAP, PAR, setup/hold TRACE and JED export using
  Diamond **3.14.0.75.2**. No FPGA or physical media was programmed by the build.
- Correct top: `ucode_sd_microcomp`; part: LCMXO2-1200HC-4SG32C.
  **1095/1280 LUT4, 548/640 slices, 431 registers, 7/7 EBR,
  17 PIO + JTAGENB.** All active pins retain their board assignments.
- Constraint **26.600 MHz**, reported internal maximum **37.627 MHz**,
  **0 setup/hold errors**, **0 unrouted connections**. This is not an
  external SPI timing measurement. The original unused-pin/synthesis/
  disabled-configuration-port warnings remain; BITGEN DRC reports zero
  errors and zero warnings, with the preloaded-EBR wake-up advisory.

Mac simulation and Ubuntu synthesis MEM/EBR files matched byte-for-byte.
SHA-256 identities for this build:

```text
sd_fram_diag.mem
7d5558625d38238fbbc7d4221be63abb16c710467772bb68250d706fa6e390df
sd_fram_diag_ebr.v
7e063a0142f82d7448fa079790a35916c29bb9702ceeaaaa1eb0f0711f85ad10
microcomp-diag_impl1.jed
e96da6a6bf5d199502d07756e49538d7992785a79600b031877ed7b36f1135a8
```

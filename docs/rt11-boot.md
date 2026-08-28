# RT-11 on the microcoded J-11 / SPI SD prototype

The complete SD + FIS image has now booted in both the wire-level testbench
and the physical HC1200. Use the `ucode` disk+FIS build selected by the main
`microcomp.ldf`. The original CPU and preserved `j11` profile remain
unchanged. No RT-11 disk image or generated microcode is committed.

## Reproduce on the Mac

From the repository root:

```sh
# Full wire-level simulation, compiled by Verilator (--binary --timing).
make -C testbench -f Makefile.disk rt11-boot-fast \
  RT11_IMAGE=/Users/sash/Work/PROJECTS/k1801vm1/lsi11/disks/rt11v503.dsk

# Independent, shorter Icarus check of both bootstrap sectors and entry PC.
make -C testbench -f Makefile.disk rt11-bootstrap-test

# Actual board top: power-on reset, safe SD failures and RESET/50-Hz WAIT.
make -C testbench -f Makefile.disk hc1200-sd-test
make -C testbench -f Makefile.disk disk-cold-boot-fast
make -C testbench -f Makefile.disk disk-cold-boot-ebr-test LATTICE_SIM_DIR=/path/to/machxo2/models

# The same complete boot/console scenario with Icarus (substantially slower).
make -C testbench -f Makefile.disk rt11-boot-test

# Optional instruction trace / larger simulation budget.
make -C testbench -f Makefile.disk rt11-boot-fast \
  RT11_VERIFY_ARGS='--trace --max-cycles 2000000000'

# Transport regressions, read-only image overlay, and absent-MMU probes.
make -C testbench -f Makefile.disk disk-test disk-image-test disk-no-mmu-test
```

`RT11_IMAGE` defaults to the sibling `k1801vm1/lsi11/disks/rt11v503.dsk`.
The supplied image is 27,540,480 bytes / 53,790 sectors. Its SHA-256 is:

```
e769228f2e1262220297bfa98b8f2841688849ab4c49ad9cd48d0d73d0a99553
```

Logs are under `testbench/build/rt11-verilator/`, `rt11-icarus/` or
`rt11-bootstrap/`: raw UART `console.log`, progress `simulation.log`, optional
guest-instruction `trace.log`, and `result.json` with input hashes and checks.
The complete test requires the RT-11FB V05.03 banner, the response to
`SHOW CONFIGURATION` (DM0:RT11FB, PDP 11/73A, 56 KB), and the `RT11FB.SYS`
directory entry.
Reaching `$finish` or printing an initial banner alone is not success.

Cold-boot / 50-Hz acceptance on 2026-08-28: **1,574,968,301 clocks**, **232
sector reads**, **6 sector writes**, **5 dirty overlay sectors**, and all **43**
input bytes consumed. Both commands return to KMON, all runner checks pass,
and the source-image hash is unchanged. This run's logs are in
`testbench/build/rt11-50hz-autoboot/` (selected with
`RT11_VERIFY_ARGS='--work-dir build/rt11-50hz-autoboot'`). Relevant output:

```
RT-11FB (S) V05.03
Booted from DM0:RT11FB
Unknown Processor
56KB of memory
Extended Instruction Set (EIS)
Floating Instruction Set (FIS)
...
RT11FB.SYS   103P 26-Jan-1999
 1 Files, 103 Blocks
 51455 Free blocks
.
```

The entire scripted sequence represents about **59.2 seconds** at the board's
26.6-MHz microengine clock. This is a functional bring-up, not a throughput
claim. In particular, long DMA commands still suspend guest execution.

### FIS-enabled physical-board acceptance (2026-08-28)

The user programmed the rebuilt FIS JED from source commit `4007f49` into the
HC1200. RT-11 booted from DM0, reported 56 KiB, EIS, FIS and the 50-cycle clock,
and returned to KMON after `SHOW CONFIGURATION`. This confirms that the
default FIS-enabled image, not only the temporary NOFIS trace, boots on the
board. It does not establish the cause of the earlier silent run.

The independent arithmetic suite remains simulation evidence: five
directed/fault FIS runs and **4040/4040** exact reference cases passed on the
same FIS implementation. The repeated full RT-11 test passed all seven
runner checks, with the same 1,574,968,301 clocks and unchanged source-image
hash. Its logs are in `testbench/build/rt11-fis-recheck/`.

Fresh Diamond synthesis, mapping, routing, setup/hold checks and JED export
from that commit also passed: 1095 LUT4, 548 slices, 431 registers, 7 EBRs,
zero unrouted connections, and zero setup/hold errors at 26.6 MHz. The
existing unused-pin, configuration-port and CFG_EBRUFM WID warnings remain.
The accepted JED and reports were saved separately in
`boards/hc1200-microcomp/impl1-sdboot/fis-recheck-4007f49/` on Mac and Ubuntu.
JED SHA-256:

```text
a1e29e7aacd392c8a234b110626d2280c34223baddd9aa8ad7ec8e825dff7e2d
```

At that source revision the maintenance register read zero. Thus MAINT[8]
correctly said that no optional FPA accelerator was installed, while module-ID
bits 7:4 also read zero and made RT-11 print `Unknown Processor`. RT-11's separate
`Floating Point Microcode` line is its no-FPA description; it does not mean
that FP11 has been implemented. FIS is detected and printed separately.

### KDJ11-A-compatible identification (simulation, 2026-08-28)

The specialized `ucode` profile now returns octal `000020` from MAINT
(`177750`): module-ID bits 7:4 are 1, while the FPA bit and all other bits
remain zero. MFPT still returns 5. Word and byte writes are ignored and RESET
preserves the constant. This identifies a compatible module; it does not add
the real KDJ11-A's MMU, FP11, cache, power-up options or console ROM. The old
`j11` profile still returns zero and its firmware is unchanged.

The full wire-level RT-11 test on the Mac, using the same unmodified input
image, prints the following actual UART output:

```text
PDP 11/73A Processor
56KB of memory
Floating Point Microcode
Extended Instruction Set (EIS)
Floating Instruction Set (FIS)
Cache Memory
50 Cycle System Clock
```

The runner now requires `PDP 11/73A Processor`, in addition to its previous
boot/console/directory checks. Logs are in `testbench/build/rt11-kdj11a/`.
All **8/8 checks passed**: **1,577,603,541 clocks**, 232 sector reads, 6 writes
to 5 dirty overlay sectors, all 43 command bytes received, and a fresh KMON
prompt after both commands. `DIRECTORY SY:RT11FB.SYS` reported 103 blocks and
51455 free blocks. The source-image SHA-256 above was unchanged.

Regressions also passed: the new and preserved MAINT word/byte tests,
**600 absent-MMU accesses** on the complete SD/FRAM bus, **209/209 core
snapshots** including 29 EIS cases, the ordinary guest/peripheral/HALT/FIS
suites, and the no-FIS trap test. The actual board-top simulation passed
UART TX/RX, guest RESET and two 50-Hz WAIT interrupts. All 14 board/diagnostic
project and MEM/EBR consistency checks passed; native SD/FRAM diagnostic
firmware is byte-identical to its prior accepted version.

Only the assembled microcode changed: four additional code words, no extra
context words or RTL changes. The normal SD+FIS image is now
**3501 code + 64 context + 19 free = 3584** words. Its MEM SHA-256, also matching
the testbench's autoboot image, is:

```text
486059bae5ee65f89711de00d553445f555c0a310c3c72682eec0ea9da2abc60
```

The hardware and Diamond results above belong to the earlier zero-MAINT
image. No Diamond build or physical-board test was performed for this
identification change; regenerate the JED before testing it on the board.

### Other simulation coverage

The independent two-sector Icarus check reaches RT-11's `000604` entry in
**1,688,185 clocks** with all 1024 bytes matching the disk. The seven board-top
cold-boot scenarios pass both Verilator and Icarus; the normal path (including
RESET and two clock interrupts) takes **2,679,094 clocks**. The same normal
and second-sector-failure/recovery paths pass with the actual Lattice EBR
models and the board ROM. The optional no-FIS board ROM also cold-boots and
passes RESET/WAIT checks in Icarus.

The preceding MMU correction's broader regression results (`fc96c39`):

- Ordinary `ucode` guest/peripheral/HALT/CPU-I/O suites pass; the ordinary
  and disk images each pass **209/209** core snapshots (29 EIS cases).
- The disk+FIS image passes **4040/4040** exact FIS cases.
- **22/22** synthetic disk scenarios (with/without FIS), four read-only
  image/overlay scenarios, invalid image sizes, and no-FIS traps pass.
- Actual Lattice EBR simulation passes the normal/partial-DMA/cache-fault
  disk scenarios, FIS/edge programs, and the **600** absent-MMU accesses on
  the complete SD/FRAM bus. These are simulation models, not a Diamond build.
- All nine original/preserved RTL and firmware files still match `d4dabf1`;
  the preserved profile's original MMU-stub/register test passes as well.

For the cold-boot follow-up, ordinary guest/peripheral/FIS/HALT/CPU-I/O tests,
both 209-snapshot core configurations, all 22 disk scenarios, image/overlay
tests and the 600 absent-MMU accesses were rerun successfully. The exhaustive
4040-case FIS sweep above belongs to the preceding commit; FIS arithmetic has
not changed. That revision's board and cold-boot test ROM SHA-256 agreed:

```
988397799b643e75985317c53b59b0f5f6e87479cf58acb6856bc97b32f23a41
```

## Power-on bootstrap

`make -C boards/hc1200-microcomp` builds **SD + FIS + autoboot** for the main
`microcomp.ldf`. The older `make -C boards -f Makefile.disk disk-ucode` command
remains supported; both use the same shared rules and images.
The explicit no-FIS disk build also boots from SD. Both define
`J11_SD_AUTOBOOT`; regular CPU/disk diagnostics omit it to enter their
preloaded guest tests. `testbench/build/j11_sd_boot.words` matches the board
`j11_sd.mem`, and the EBR cold-boot test uses the board's generated EBR file.

The SD board top initializes a two-stage generic reset synchronizer at FPGA
configuration. After context clearing, the initial microcode entry resets
peripherals and jumps to `sd_boot` in `ucode/experimental/rh11_sd.asm`:

1. Set RH0 WC to `-01000` (512 words), BA/DA/DC/unit already zero; READ + GO.
2. Initialize SDHC/SDXC and read **sectors 0 and 1**, through the existing SD
   command/cache/DMA routines, into guest FRAM `000000..001777`.
3. Require completion without RH errors and WC zero. Set R1=`177440`,
   SP=`02000`, R4=`02020`, PSW=`4`; R0/R2/R3/R5/PC retain reset zero.
4. Fetch guest code at address 0. **Nothing needs to be installed in FRAM.**

This is the entry ABI of `lsi11/main.c` / `j11_programs/rh11_boot.asm` after
its `CLR PC`. The latter remains an assembled reference, but is no longer
deposited by either RT-11 test. The bootstrap adds **26 native code words**.
Guest `RESET` calls only the peripheral reset path, never `sd_boot`.

Transport failure, including a failed second sector, stops in a microcode
loop with private diagnostic **cause 5** and RH error/WC/BA status retained.
SD CS is released and the FRAM bank override is off. No stale/partially loaded
guest instruction runs, and console Proceed cannot bypass the failure.
Fixing/inserting the card and asserting the board reset retries the boot.
There is no boot-menu/ODT/error-message UI or filesystem/signature validation.

## What is actually simulated

The RT-11 tests now begin with **empty FRAM**, not a deposited bootstrap.
The shorter Icarus test compares all 1024 loaded bytes against the image before
RT-11's own code at `000604` runs. A separate board-top test never asserts
external reset on power-on and also boots from stale `A5`-filled FRAM.
Its disk boot block (`sd_cold_boot.asm`) is assembled by **microasm11**.
It checks boot registers, guest RESET without disk reload/RAM loss and two
WAIT/vector-100 interrupts. Five fault scenarios cover absent SD, first/second
sector errors, wrong OCR and wrong CMD8 echo, followed by reset/recovery.

The full test uses the real `ucode_cpu`, assembled disk+FIS microcode, native
bus services, SPI FRAM controller and serial UART. The SD card model parses
SPI command/data frames and reads sectors from the supplied raw file. Board
clock divisors are retained, not a fast-memory or direct-RH11 substitute.
The test clock's nanosecond scale is arbitrary; physical time is the reported
clock count divided by 26.6 MHz. Active `ucode`/SD tops now use **532000 clocks
per tick: nominally 50 Hz**. The full test checks 50 native ticks per 26.6M
clocks; the board test checks consecutive intervals and continuity across
guest RESET. SD timeouts are 100 ticks (~2 seconds), power settling waits two
tick transitions. Long synchronous DMA still coalesces missed guest clock
interrupts: this does **not** yet guarantee accurate RT-11 time under disk load.
A monitor's printed text is not proof of every advertised hardware option. Its printed
`Cache Memory` / `FPU support` lines do not mean that this prototype acquired
a data cache or FP11; FP11 is still out of scope.

UART output is decoded from the TX pin with stop-bit checks. Commands enter
through RX as 115200 8N1 frames. A paced terminal waits for the one-byte
hardware/software receive buffers to drain; this is not a sustained-input
throughput test. Return is explicit ASCII `\015`, portable between simulators.
Each command must produce a **new** quiet KMON prompt before the test continues.

## Protecting the source disk

The card model only opens the input as **`rb`**. Written sectors live in a
volatile RAM overlay (up to 256 dirty sectors), take precedence on subsequent
reads, and disappear when the simulation exits. The original is never opened
for writing. A full overlay or malformed/short backing file fails explicitly.
The runner additionally compares SHA-256 before and after both successful and
failed simulations. Separate synthetic tests cover normal writes, rejection,
partial DMA and cache-fill faults against a read-only backing file, and compare
the complete effective medium rather than only checking controller DONE.

## No-MMU correction found by this boot

The initial run hung in the RT-11 memory-sizing loop at `005212..005264`.
Our previous zero-read/write-ignore MMU stubs made the bus probe succeed.
RT-11 then tried to increment a PAR and access the mapped window; with an
ignored PAR write, the loop never progressed.

In the specialized **no-MMU** firmware, MMR0/1/2/3 and all S/K/U PAR/PDR
addresses now take the normal unmapped-I/O path: vector 4 and CPUERR.TMO.
This matches the reference `lsi11/Makefile` configuration
`ENABLE_MMU=0, MMU_STUB_REGS_WHEN_DISABLED=0`. It does **not** claim to implement
the MMU present in a real J-11. All behavior changes are in assembly microcode;
there is no new J-11 register or exception logic in Verilog.

`cpu_mmu_absent.asm` checks 100 addresses × six word/byte read/write forms,
600 traps in total. Existing processor-register tests still run; the preserved
`j11` profile separately retains its historical zero/ignore tests. Removing the
misleading stubs saves 30 code words; adding autoboot spends 26. That revision's
disk+FIS image was **3497 code + 64 context + 23 free = 3584**. The subsequent
[Diamond run of `6668a85`](hc1200-sd-diamond.md) builds this exact ROM with
the new reset/divider and corrected board constraints through JED export:
1095 LUT4, 7 EBRs, zero internal timing errors at 26.6 MHz. Physical-board
acceptance is recorded above for the subsequent rebuild.

## Supplied SD connections — functionally verified

| Board site | SD signal | RTL port |
|---|---|---|
| PL9B | CS | `sd_cs_n` |
| PR5C | MOSI | `sd_mosi` |
| PT12D | SCLK | `sd_sck` |
| PT12C | MISO | `sd_miso` |

Both disk projects select `sd.lpf` with these supplied locations; the
ordinary/preserved projects are unchanged. The separate Diamond run confirms
implemented pins and internal timing. Real-card initialization, sector reads,
CRC checking and RT-11 operation have now passed on the board; physical I/O
timing margins and signal integrity have not been measured. Once configured,
the SD top's reset and uROM bootstrap do not depend on preexisting FRAM
contents or an external loader.
The disk still requires a raw RK image at SD LBA 0, not a file in a FAT volume.
See [controller scope and remaining limitations](rk611-sd-prototype.md).

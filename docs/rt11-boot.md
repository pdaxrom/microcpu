# RT-11 on the microcoded J-11 / SPI SD prototype

This is a **testbench boot**, not a physical-board acceptance test. Use the
explicit `ucode` disk+FIS build. The original CPU and preserved `j11` profile
remain unchanged. No RT-11 disk image or generated microcode is committed.

## Reproduce on the Mac

From the repository root:

```sh
# Full wire-level simulation, compiled by Verilator (--binary --timing).
make -C testbench -f Makefile.disk rt11-boot-fast \
  RT11_IMAGE=/Users/sash/Work/PROJECTS/k1801vm1/lsi11/disks/rt11v503.dsk

# Independent, shorter Icarus check of both bootstrap sectors and entry PC.
make -C testbench -f Makefile.disk rt11-bootstrap-test

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
`SHOW CONFIGURATION` (DM0:RT11FB, 56 KB), and the `RT11FB.SYS` directory entry.
Reaching `$finish` or printing an initial banner alone is not success.

Observed complete run on 2026-08-28: **1,627,665,662 clocks**, **232 sector
reads**, **6 sector writes**, **5 dirty overlay sectors**, and all **43** input
bytes consumed. Both commands return to KMON. Relevant serial output:

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

The entire scripted sequence represents about **61.2 seconds** at the board's
26.6-MHz microengine clock. This is a functional bring-up, not a throughput
claim. In particular, long DMA commands still suspend guest execution.

Regression results for the firmware correction:

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

## What is actually simulated

`j11_programs/rh11_boot.asm` is assembled by **microasm11**. It expresses the
RH0 bootstrap in `lsi11/main.c`: code at octal `02000`, entry `02002`, controller
at `177440`, WC `-01000` (512 words = **two** 512-byte sectors), load address 0,
then `CLR PC`. A small jump at reset address 0 initially enters this bootstrap.
That jump is overwritten by the real disk read. No OS or disk boot block is
preloaded into guest RAM. The shorter Icarus test compares all 1024 loaded
bytes against the image before RT-11's own code at `000604` runs.

The full test uses the real `ucode_cpu`, assembled disk+FIS microcode, native
bus services, SPI FRAM controller and serial UART. The SD card model parses
SPI command/data frames and reads sectors from the supplied raw file. Board
clock divisors are retained, not a fast-memory or direct-RH11 substitute.
The test clock's nanosecond scale is arbitrary; physical time is the reported
clock count divided by 26.6 MHz. The raw time source retains the board default
of 60 ticks/second. A monitor's printed clock/configuration text is not a
measurement of this time source or proof of every advertised hardware option.
This image prints **50 Cycle System Clock**: align the clock configuration to
50 Hz before relying on guest wall-clock time on a physical board. Its printed
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
misleading stubs saves 30 code words: **3471 code + 64 context + 49 free = 3584**
for disk+FIS. The last Diamond resource/timing numbers refer to the preceding
firmware, not a rerun of this change.

## Supplied SD connections — not yet electrically verified

| Board site | SD signal | RTL port |
|---|---|---|
| PL9B | CS | `sd_cs_n` |
| PR5C | MOSI | `sd_mosi` |
| PT12D | SCLK | `sd_sck` |
| PT12C | MISO | `sd_miso` |

These connections are recorded for the later physical-board step. No Diamond
run, programming, real-card write or new pin-constraint activation is part of
this test. Boot provisioning on the physical board remains separate: the
testbench deposits the assembled bootstrap in FRAM, not in production uROM.
The disk still requires a raw RK image at SD LBA 0, not a file in a FAT volume.
See [controller scope and remaining limitations](rk611-sd-prototype.md).

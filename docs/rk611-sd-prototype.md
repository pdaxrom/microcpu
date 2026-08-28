# Experimental microcoded RK611/RH11 → SPI SD

This is a **working bring-up prototype, not a production disk controller**.
The original `j11` and no-disk `ucode` images remain separate. The main
`hc1200-microcomp/microcomp.ldf` now selects SD + FIS + power-on boot.
The supplied SD pins are recorded in `sd.lpf` and confirmed by the final
Diamond PAD report. SD reads and RT-11 boot have passed on the physical board;
external I/O timing margins remain uncharacterized. The build commands do
not program a board or card. The experimental
`build-sd.tcl` does not export JED; the main project's `build-microcomp.tcl`
passed timing checks and exported JED in the [current build](hc1200-sd-diamond.md).

## Resource result

HC1200 has seven EBRs: 3584 16-bit words with this packing, of which 64 are
context RAM. The code limit is therefore **3520 words**.

| Configuration | Code | Context | Free code words | EBR required |
|---|---:|---:|---:|---:|
| Normal ucode + FIS, no disk | 2826 | 64 | 694 | 7 allocated |
| Explicit disk + FIS + power-on bootstrap | 3501 | 64 | **19** | **7; fits** |
| Explicit disk/no-FIS + power-on bootstrap | 3181 | 64 | 339 | 7 |

The RT-11 follow-up removes 30 words of misleading MMU stubs, then adds
26 words for the power-on bootstrap; see [cold boot and tests](rt11-boot.md).
The latest Diamond check (`a985039`, 2026-08-28) includes these changes, the
50-Hz divisor, reset synchronizer, corrected board pin/pull constraints and
the four-word KDJ11-A identification handler. The figures above are for that
revision. See [the specialized engine](ucode-cpu.md) for CPU scope.

The complete disk+FIS board, not just the SPI block, uses **1095/1280 LUT4,
548/640 slices, 431 registers, 7/7 EBRs and 17 PIO + JTAGENB**. TRACE reports
**37.627 MHz**, with no setup/hold violations at the unchanged 26.6-MHz
constraint. All 17 active pins are locked to the board's specified sites,
and JED export passes. External I/O timing/electrical checks remain separate;
see the [build report and warnings](hc1200-sd-diamond.md). The earlier
pre-autoboot result was 1099 LUT4 / 552 slices / 429 registers / 39.987 MHz.

The earlier full image needed 3645 code words, 125 beyond capacity. Shorter
far-branch macros save 38 words, CBZ/CBNZ save 82, FIS ADC/SBC chains and shifts
save 20, and disk LBA carry chains save four: **144 words recovered**.
The combined ISA change costs 58 LUTs against the earlier 1041-LUT disk/no-FIS
board. Both flat simulation and the actual EBR path now use **3584 words**;
the production packer still rejects oversized images. FIS has not been removed.

## Architecture and scope

`ucode/experimental/rh11_sd.asm` implements guest registers, command dispatch,
geometry, word counts, DMA copying, completion/error status and BR5/vector
**0210** interrupts. Register addresses start at **0177440**, following
`k1801vm1/lsi11/dev_rh11.c` in RH11 mode. Context 40..55 stores the sixteen
register words; 56..60 and 63 hold private state. Scratch 25..30 is reused
only at instruction boundaries, outside the normal guest-memory helpers.

The only new synthesizable services are a generic mode-0 SPI byte engine
and a private FRAM-bank selector. There are no new J-11 architectural
registers or instruction semantics in Verilog.

| Native address | Service |
|---|---|
| F008 | Write: transmit low byte; read: transmit FF and receive a byte |
| F00A | Control bit 0: CS_n; bit 1: fast clock |
| F00C | FRAM bank override, bit 0 |

Data accesses complete after the byte finishes. Control accesses are immediate;
high-byte accesses are inert, misaligned words fail. These services are not
mapped into guest RAM. SPI defaults to divide-by-68 for initialization and
divide-by-2 afterward: about 196 kHz / 6.65 MHz at the current 26.6-MHz clock.

One sector cache occupies **512 bytes at FRAM physical 0x10000..0x101ff**.
It costs no additional EBR. Guest and disk traffic have one owner, the
microengine: transfers are serialized and cannot race the FRAM port. The
prototype performs an entire command synchronously at an instruction boundary.
It preserves pending native events, but **guest execution is blocked**, and a
long command can overrun a small UART receive buffer. Cooperative servicing
or an asynchronous transport is required before production use.

This is an operational subset, not complete RK611 register conformance.
Diagnostic/maintenance registers are placeholders, and DS uses a fixed drive-0
signature rather than a mechanical drive/card-detect state machine.

Supported behavior:

- Drive 0; other drive selections produce NED and retain the selected unit.
- READ 020 and WRITE 022, plus the reference's legacy 070/060 aliases.
  Simple function codes below 020 complete without transferring data.
  Write-check and header operations are not implemented and return ILF.
- RK geometry: three heads, 22 sectors/track, 256 little-endian words/sector.
  A 24-bit LBA is calculated from the full 16-bit cylinder field. Transfers
  can cross sector/head/cylinder boundaries; DA advances only after a full
  sector, as in the reference.
- Negative WC, byte-lane register access, word-aligned BA, BAI, controller
  clear, IE/RDY request latching and completion acknowledgement without
  clearing DONE. The current DMA window is **0..0xDFFF**; nonzero BA extensions
  and the I/O page produce NEM. This is not an 18/22-bit RH70/UBMAP implementation.
- Partial writes use read/modify/write, preserving the rest of the sector.
  A DMA fault retains successful WC/BA progress and commits only successfully
  copied write words. A failed next-sector cache fill never writes that
  incomplete cache back to SD.

SDHC/SDXC block addressing is required; SDSC/MMC are rejected. The media is a
**raw RK image starting at SD LBA 0**, not a FAT file or partition discovered
automatically. Drive 0 is treated as attached; absent/unresponsive cards are
reported by transport errors, not a physical card-detect input.

The firmware waits for power settling, supplies initial clocks, checks
CMD0/CMD8, loops CMD55/ACMD41 and validates CMD58 CCS. Reads use CMD17;
writes use CMD24, check the data response and BUSY release, then check CMD13
status. Command responses are bounded to 16 byte polls; initialization,
read-token and write-busy waits are bounded to 100 native ticks (about two seconds
at the new 50-Hz tick rate), including counter wrap. CRC checking remains
disabled in SPI default mode; CMD0/CMD8 use their required CRC values and
read data CRC bytes are consumed but not verified. A write timeout or status
error can occur after media has changed: failure does not promise rollback.

Protocol references: [SD Association physical-layer specification 3.01,
SPI chapter (primary document hosted by UT Austin)](https://www.cs.utexas.edu/~simon/395t_os/resources/Part_1_Physical_Layer_Simplified_Specification_Ver_3.01_Final_100518.pdf)
and [Analog Devices AN-1443](https://www.analog.com/en/resources/app-notes/an-1443.html).

## Reproduce

From the repository root:

```sh
# Full + no-FIS wire-level SD/FRAM simulations; guest sources use microasm11.
make -C testbench -f Makefile.disk disk-test disk-nofis-test
make -C testbench -f Makefile.disk disk-core-test disk-fis-test FIS_JOBS=8
make -C testbench -f Makefile.disk disk-nofis-disabled-test
make -C testbench -f Makefile.disk disk-ebr-test disk-nofis-ebr-test LATTICE_SIM_DIR=/path/to/machxo2/models

# Full SD+FIS .mem and vendor EBR initialization, with capacity checking:
make -C boards -f Makefile.disk disk-ucode

# Power-on boot/RESET/50-Hz WAIT and failed-card recovery, actual board top:
make -C testbench -f Makefile.disk disk-cold-boot-fast
make -C testbench -f Makefile.disk disk-cold-boot-ebr-test LATTICE_SIM_DIR=/path/to/machxo2/models

# In an isolated Ubuntu build directory; no SD JED export/programming:
make -C boards -f Makefile.disk disk-diamond DIAMOND_HOME=/home/sash/.local/lscc/diamond/3.14
# Explicit optional no-FIS configuration remains available:
make -C boards -f Makefile.disk disk-nofis-diamond DIAMOND_HOME=/home/sash/.local/lscc/diamond/3.14
```

Tests compare the entire simulated 128-KiB SD image after each scenario,
not just controller DONE. The independent card model parses real SPI command
frames and supplies delayed responses/tokens and write BUSY. The corpus covers
normal read/partial write, boundary crossing, BAI, byte lanes, IRQ latching,
controller clear, invalid geometry/function/drive/BA extension, absent card,
bad read token, rejected write, stuck BUSY, wrong OCR/CMD8 echo, 24-bit LBA,
late programming error, partial DMA fault and next-sector cache fault.
The last fault specifically guards against committing an incomplete cache.

Final acceptance on 2026-08-28: **22/22 disk scenarios** (eleven each with
and without FIS), **209/209 J-11 core snapshots** including 29 EIS cases,
and **4040/4040 exact FIS cases** pass. The explicit no-FIS build traps FIS
instructions. Actual Lattice DP8KC simulation passes normal transfers,
partial DMA faults and next-sector cache faults with both images, plus FIS
and FIS-edge programs on the full image. Native SPI tests cover 512 byte/speed combinations, held requests,
read completion, alignment and reset during a transfer.

The ordinary ucode native/guest/peripheral/core suites passed that run. All nine
original/preserved profile source files still match `d4dabf1`. The new normal
FIS ROM SHA-256 is
`a874745b302008bcf6659f3f52bb67dddcefb79dc2e634a122d35de77a792781`.
The pre-RT-11 full disk+FIS ROM hash agreed between Mac simulation and the isolated
Ubuntu Diamond build (historical image, not the current autoboot ROM):
`234dc454156e3a1d4c0e402e85b171374f8fb43728c126177ecff71b1a2b97df`.
Generated images and reports remain ignored build artifacts.

The board disk builds now define `J11_SD_AUTOBOOT`. Diagnostic test images
omit that definition to execute preloaded guest assembly; their generated
EBR files are separate from the board's autoboot EBR. RT-11 and cold-boot
tests use `j11_sd_boot.words`, byte-for-byte equal to the board `j11_sd.mem`.

Remaining work before production use: make long transfers cooperative,
extend controller/card compatibility as needed, add data CRC checking to the
normal firmware, and characterize external I/O timing margins. Diagnostics
already check CRC, but they are separate images. Physical transport checks
and RT-11 boot are recorded in [RT-11 acceptance](rt11-boot.md); they do not
prove compatibility with every card or all controller commands. See
[specialized board preparation and UART pins](hc1200-microcomp-ucode.md).

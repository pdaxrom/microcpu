# Experimental microcoded RK611/RH11 → SPI SD

This is a **simulation/resource prototype, not a production disk controller**.
It never replaces the accepted `j11` or `ucode` images. The normal ucode
configuration still includes FIS. No SD pins have been assigned or board/card
programming performed; the experimental Diamond script does not export JED.

## Resource result

HC1200 has seven EBRs: 3584 16-bit words with this packing, of which 64 are
context RAM. The code limit is therefore **3520 words**.

| Configuration | Code | Context | Free code words | EBR required |
|---|---:|---:|---:|---:|
| Accepted ucode + FIS, no disk | 2968 | 64 | 552 | 7 allocated |
| Disk + FIS | 3645 | 64 | **−125** | **8; does not fit** |
| Explicit disk/no-FIS prototype | 3298 | 64 | 222 | 7 |

The complete disk/no-FIS board, not just the SPI block, uses **1041/1280 LUT4,
523/640 slices, 423 registers, 7/7 EBRs and 17 PIO + JTAGENB**. TRACE reports
**41.943 MHz**, with no setup/hold violations at the unchanged 26.6-MHz
constraint. These are internal placement/timing estimates; SD I/O timings and
automatically selected experimental pins are not a validated board pinout.

The disk logic costs 82 LUTs compared with the accepted engine/board. Logic
fits; microcode capacity is the obstacle to retaining FIS with this prototype.
The full variant is tested in a **4096-word simulation-only image**. The
production EBR packer continues to reject it instead of truncating code.

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
read-token and write-busy waits are bounded to 120 native ticks (two seconds
at the standard tick rate), including counter wrap. CRC checking remains
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
make -C testbench -f Makefile.disk disk-nofis-ebr-test LATTICE_SIM_DIR=/path/to/machxo2/models

# Expected to FAIL capacity checking, never truncate or silently drop FIS:
make -C boards -f Makefile.disk disk-ucode

# Explicit alternative, in an isolated Ubuntu build directory:
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
partial DMA faults and next-sector cache faults with the fitting no-FIS
image. Native SPI tests cover 512 byte/speed combinations, held requests,
read completion, alignment and reset during a transfer.

The ordinary ucode native/guest/peripheral/core suites pass again. All nine
original/preserved profile source files still match `d4dabf1`, and the normal
FIS ROM retains its stage-4 SHA-256:
`0ea83148ca9328b9a5afa4a42026e124724e07948874412457c4ab44d3b33f20`.
The final disk/no-FIS ROM hash agrees between Mac simulation and the isolated
Ubuntu Diamond build:
`f672cf5613e3fec71cca3d2d3bcbda81346a378a64dbb68677365c05de229ef5`.
Generated images and reports remain ignored build artifacts.

Remaining work before hardware use: recover at least 125 code words (or
design an explicit code-overlay scheme) while retaining FIS; make long
transfers cooperative; extend controller/card compatibility as needed; add
data CRC checks; confirm electrical connections, pin constraints and I/O
timing. No disk-enabled production configuration is selected automatically.

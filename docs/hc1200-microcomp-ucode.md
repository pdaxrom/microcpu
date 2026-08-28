# HC1200 microcomp: specialized engine and SD boot

[Legacy microcomp](hc1200-microcomp.md) · [Preserved J-11 microcomp](hc1200-microcomp-j11.md) ·
[Specialized CPU](ucode-cpu.md) · [Diamond](diamond.md) · [Simulators](../testbench/README.md)

These are FPGA configurations of the existing microcomp PCB, all using
`rtl/ucode_cpu.v` and native `--cpu ucode` firmware. They are not new CPU
profiles or new board revisions.

## Stable J11 / RT-11 SD boot

**The configuration programmed into the board and confirmed working is
`microcomp.ldf`, implementation `impl1` in directory `impl1-sdboot`.** This is
the stable J11 microcode with RT-11 SD boot, not `microcomp-j11.ldf`, the
no-disk `microcomp-ucode.ldf`, or either diagnostic project.

| Stable baseline | Value |
|---|---|
| Source commit | `a985039cbc407746ed2ad38eb44c76b28821eb7c` |
| Native CPU / top | `ucode` / `ucode_sd_microcomp` |
| Firmware | `ucode/v2/j11.asm` + `ucode/experimental/rh11_sd.asm` |
| Build features | `J11_DISK_PROTOTYPE`, `J11_SD_AUTOBOOT`; FIS enabled |
| Configuration | No MMU, EIS + FIS, 56 KiB guest RAM, 50-Hz clock, 115200 8N1 |
| Generated JED | `impl1-sdboot/microcomp_impl1.jed` |
| Exact flashed copy | `impl1-sdboot/kdj11a-a985039/microcomp_impl1.jed` |
| JED checksum | `5C98` |
| Confirmed boot | RT-11FB V05.03 from DM0; `PDP 11/73A Processor` |

Paths in the JED rows are relative to `boards/hc1200-microcomp/`.
The stable designation identifies this tested board/image baseline, not full
J-11 hardware equivalence or every SD card. Existing limitations remain below.
The exact JED SHA-256, successful FLASH verify and hardware boot evidence are
in [the acceptance report](hc1200-sd-diamond.md).

## Configuration map

| Configuration | Project | Top | Constraints |
|---|---|---|---|
| No-disk specialized J-11 | `microcomp-ucode.ldf` | `ucode_hc1200_microcomp` | `j11.lpf` |
| **Stable J11 / RT-11 SD boot** (build default) | `microcomp.ldf` | `ucode_sd_microcomp` | `sd.lpf` |
| Native SD/FRAM diagnostic | `microcomp-diag.ldf` | `ucode_sd_microcomp` | `sd.lpf` |
| Temporary NOFIS boot trace | `microcomp-boot-trace.ldf` | `ucode_sd_microcomp` | `sd.lpf` |

All projects are under `boards/hc1200-microcomp/`. The explicit
`microcomp-sd.ldf` and `microcomp-sd-nofis.ldf` are separate resource/timing
experiments; their CLI targets do not export JED. Use the main project for
the normal SD firmware.

## J-11 / SD boot (default project)

`boards/hc1200-microcomp/microcomp.ldf` now selects **J-11 without MMU,
EIS + FIS, a 50-Hz clock, and RK611-compatible SD boot**. Its top is
`ucode_sd_microcomp`, with the generated `sd_urom_ebr.v` and `sd.lpf`.
The original RISC hardware is preserved as `microcomp-original.ldf`;
`microcomp-j11.ldf` and the no-disk `microcomp-ucode.ldf` remain separate.

From the repository root, prepare the firmware before opening Diamond:

```sh
make -C boards/hc1200-microcomp
# Equivalent: make -C boards hc1200-microcomp
```

This builds `microasm` if necessary, assembles the SD-autoboot microcode and
generates `j11_sd.mem` / `sd_urom_ebr.v`. It works on the Mac without Diamond
or SCUBA. The repository-wide `make -C boards all` also includes these images,
but still generates the other/legacy boards' SCUBA RAMs and needs Diamond.
Generated files are not committed.

The diagnostic sources and their Diamond projects are committed separately;
they regenerate their own BIN/MEM/EBR/JED artifacts and never replace the
default project. Run each target with `make -C boards/hc1200-microcomp TARGET`:

| Image | Portable uROM target | Diamond/JED target | Project / output |
|---|---|---|---|
| J-11 + FIS + SD autoboot | `all` (default) | `diamond` | `microcomp.ldf` / `impl1-sdboot/microcomp_impl1.jed` |
| Native SD/FRAM transport diagnostic | `diag` | `diag-diamond` | `microcomp-diag.ldf` / `impl1-diag/microcomp-diag_impl1.jed` |
| J-11 SD boot trace, temporarily no FIS | `boot-trace` | `boot-trace-diamond` | `microcomp-boot-trace.ldf` / `impl1-boot-trace/microcomp-boot-trace_impl1.jed` |

The source entry points are `ucode/diagnostics/sd_fram.asm` and
`ucode/diagnostics/boot_trace.asm`; shared rules are in
`boards/diagnostics.mk` and `boards/sd.mk`. See the
[transport diagnostic](hc1200-diagnostics.md) and
[boot-trace diagnostic](hc1200-boot-trace.md) instructions before programming.

Open **`microcomp.ldf`** in Diamond and run through **JEDEC File**. To build
from the Ubuntu command line instead (build/export only, never program):

```sh
make -C boards/hc1200-microcomp diamond \
  DIAMOND_HOME=/home/sash/.local/lscc/diamond/3.14
```

The output is `impl1-sdboot/microcomp_impl1.jed`. This separate implementation
directory avoids reusing the old RISC results or its stale `impl1.xcf`.
Select this JED explicitly when later configuring Programmer. The script
exports only after TRACE reports zero cumulative negative slack. Commit
`a985039` passed the full Diamond build through JED: 1095 LUT4, 548 slices,
7 EBRs, zero setup/hold errors at 26.6 MHz (TRACE maximum 37.627 MHz).
See [the build report, implemented pins and warnings](hc1200-sd-diamond.md).
The latest JED passed FLASH program/verify, then the user confirmed RT-11
boot and `SHOW CONFIGURATION` with `PDP 11/73A Processor`. Earlier board runs
also passed native SD/FRAM diagnostics and the NOFIS boot trace. External
SPI timing margins are still not characterized. See the [Diamond guide](diamond.md)
for tool setup, build checks and programming; none of the make targets flashes
the board.

UART and SD locations come from the board's existing `microcomp.lpf`:

| Signal (FPGA perspective) | Site | Connection |
|---|---|---|
| `rx` | **PT15D** | UART adapter TX |
| `tx` | **PT17D** | UART adapter RX |
| `sd_cs_n` | PL9B | SD CS |
| `sd_mosi` | PR5C | SD MOSI |
| `sd_sck` | PT12D | SD clock |
| `sd_miso` | PT12C | SD MISO |

Console settings: **115200, 8N1, no flow control**, 3.3-V UART levels and a
common ground. RX and TX have not been swapped. The four former GPIO sites
are now assigned to SD, not simultaneously to two ports. Guest console
registers are the microcoded DL11 at octal `177560..177566`.

`sd.lpf` preserves the **entire original `microcomp.lpf`**, changing only
`gpio[0..3]` to `sd_cs_n`, `sd_mosi`, `sd_sck`, `sd_miso` in the IOBUF and
LOCATE entries. UART RX/TX, all four SD signals, FRAM and display signals
retain `PULLMODE=NONE`; reset retains `UP`, and keyboard rows retain `DOWN`.
All other locations, I/O types and SYSCONFIG settings are unchanged. The SD
top has no leftover generic `gpio[0..3]` ports. This preserves the board's
existing electrical configuration; simulation does not verify physical pulls.

After FPGA configuration or board reset, uROM reads sectors 0 and 1 from
SD into FRAM and enters guest address 0. FRAM needs no preinstalled bootstrap.
Use an **SDHC/SDXC card with a raw RK disk image at LBA 0**, not a file in FAT.
Guest `RESET` does not restart the boot. ODT remains deferred.
See [boot tests and limits](rt11-boot.md) for details and the verified RT-11 image.

Mac verification of the selected project, both UART pins and SD cold boot:

```sh
make -C testbench -f Makefile.disk hc1200-sd-test
```

The program is assembled by `microasm11`, loaded only into the simulated SD,
and checks a TX `'U'` / RX `'Z'` exchange through the actual board ports.
Project/ROM/pin consistency, exact LPF preservation (including pull modes),
top-level port coverage and build-script error gates are checked as well;
the latter uses mocked Diamond commands and is not a synthesis result.


## No-disk specialized configuration

`microcomp-ucode.ldf` uses `ucode_microcomp.v`, the generated
`j11_ucode_v2.mem` / `ucode_urom_ebr.v`, and the same raw UART/FRAM services
as the preserved board. Its tick divisor is 532000 (50 Hz at 26.6 MHz).
The four general GPIO pins remain high impedance and the display is blanked;
there is no SD-byte service or SD bootstrap. Guest code must already be in
FRAM. HALT/Proceed does not yet provide an ODT terminal.

```sh
# Image generation: Mac or Linux.
make -C boards j11-v2-ucode
# Ubuntu / Diamond: full build and JED export, no programming.
make -C boards j11-v2-diamond DIAMOND_HOME=/home/sash/.local/lscc/diamond/3.14
```

The JED is `impl1-ucode/microcomp-ucode_impl1.jed`. Do not load a reference
`j11_ucode.mem` into this CPU: the native encodings differ. See
[CPU profiles](cpu-profiles.md#separate-builds) for the complete image map.

## Memory and limitations

The SD+FIS board at source `a985039` uses 1095 LUT4, 548 slices, 431 registers
and all seven EBRs. The shared uROM/context allocation is
**3501 code + 64 context + 19 free = 3584 words**. Guest stacks and RAM are in
the external FRAM, not in uROM. A 512-byte disk-sector cache uses the second
FRAM bank; no EBR is allocated to it.

On physical hardware, normal guest disk writes modify the SD card. This is
different from the simulator's read-only source image plus volatile overlay.
Keep a backup of the raw disk image. SD/FRAM signal margins have not been
measured, and long disk commands block guest execution. See
[RT-11 acceptance](rt11-boot.md) and [controller scope](rk611-sd-prototype.md).

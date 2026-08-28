# Lattice Diamond: build and programming

[Main README / legacy CPU](../README.md) · [CPU profiles](cpu-profiles.md) ·
[Legacy hardware](hc1200-microcomp.md) · [J-11 hardware](hc1200-microcomp-j11.md) ·
[Specialized hardware](hc1200-microcomp-ucode.md) · [Simulators](../testbench/README.md)

This guide covers the HC1200 microcomp projects, target
**LCMXO2-1200HC-4SG32C (QFN32)**. Image generation, FPGA implementation and
programming are separate operations. None of the repository's Diamond make
targets erases/programs the FPGA or writes an SD card.

## Host setup

The recorded builds use **Diamond 3.14.0.75.2 on Ubuntu x86-64**. Install the
MachXO2 tools and configure the license required by the selected Synplify Pro
synthesis flow. Build tools also require make, a C compiler and Python 3.
The examples below run from the repository root.

For the stable J11 / RT-11 baseline, the bundled synthesis tool was
**Synplify Pro V-2023.09L-2, Build 349R** on **Ubuntu 24.04.4 LTS x86-64**,
using `Strategy1` from `j11.sty`. The full Diamond version is
**3.14.0.75.2**; the installation directory name `3.14` alone is not an
exact version identifier. Check the JED/BITGEN/TRACE headers and synthesis
`.srr` when recording a build.

Another tool version or strategy can generate a different configuration,
timing result and JED hash from unchanged sources. Full-file SHA-256 also
covers the JED header, including its creation timestamp, so even the same
toolchain does not guarantee an identical file hash. The published checksum
and SHA-256 identify the archived, physically tested JED; qualify new builds
separately. See [stable build identity](hc1200-sd-diamond.md).

`boards/Makefile` defaults to:

```text
DIAMOND_HOME=$HOME/.local/lscc/diamond/3.14
DIAMOND_LIBSTDCPP=/lib/x86_64-linux-gnu/libstdc++.so.6
```

Override `DIAMOND_HOME` for another installation; do not substitute the
standalone Programmer directory. The make recipes set `LD_PRELOAD` to the
system C++ library for the Ubuntu compatibility workaround; SCUBA recipes
also set `FOUNDRY` and the tool library paths. Keep this environment local
to Diamond rather than exporting its old bundled libraries globally. The
system-library path is Ubuntu-specific; override `DIAMOND_LIBSTDCPP` on a
different host. Historical WSL rules exist but are not the tested 3.14 flow.

macOS needs no Diamond to assemble microcode or run Icarus/Verilator. Only
the `original` board SRAM preparation uses SCUBA; the two microengines use
the repository's Python EBR packer. Generated BIN/MEM/EBR/JED files are
build products and must not be edited or committed.

## Choose the matching project

All LDFs, generated memory files and implementation directories below are
under `boards/hc1200-microcomp/`. The project and top must match the firmware:

| Configuration | LDF | Top | Prepare from repository root |
|---|---|---|---|
| Legacy RISC | `microcomp-original.ldf` | `demo` | `make -C boards/hc1200-microcomp original` |
| Preserved `j11` | `microcomp-j11.ldf` | `j11_hc1200_microcomp` | `make -C boards j11-ucode` |
| Specialized `ucode`, no disk | `microcomp-ucode.ldf` | `ucode_hc1200_microcomp` | `make -C boards j11-v2-ucode` |
| **Stable J11 / RT-11 SD boot** | `microcomp.ldf` | `ucode_sd_microcomp` | `make -C boards/hc1200-microcomp` |
| Native SD/FRAM diagnostic | `microcomp-diag.ldf` | `ucode_sd_microcomp` | `make -C boards/hc1200-microcomp diag` |
| NOFIS boot trace | `microcomp-boot-trace.ldf` | `ucode_sd_microcomp` | `make -C boards/hc1200-microcomp boot-trace` |

Legacy is the main documentation reference, but the existing default LDF
and board make target select SD boot. A different top can synthesize without
representing this board: missing `rx`, `tx`, `res` or SD ports in the LPF
warnings are a reason to stop and check project selection.

## GUI build

1. Run the selected preparation command above. Diamond does not assemble
   `.asm` sources automatically; regenerate the memory after firmware edits.
2. Open that exact `.ldf`. Check its top, device, source list and LPF. Legacy
   uses `microcomp.lpf`, no-disk microengines use `j11.lpf`, SD variants use
   `sd.lpf`. Do not transplant LPFs or change UART pulls to silence warnings.
3. Select the **Process** tab and the desired process (for a complete image,
   **Export Files → JEDEC File**), then Run. The Reports tab alone does not
   select an executable process. Inspect the first failing stage if it stops.
4. Check synthesis, MAP, PAR, setup/hold TRACE and JED export. A synthesis
   success or an old `.jed` on disk is not evidence of a complete new build.
5. Verify the current implementation directory and JED timestamp before
   opening Programmer. Old `impl1/impl1.xcf` files can refer to a different
   project, missing files or the previous firmware.

## Command-line builds

The command below builds the **stable J11 / RT-11 SD-boot configuration**
through JED export. The hardware-tested baseline is source `a985039`,
**Diamond 3.14.0.75.2**, JED checksum `5C98`; later rebuilds must be verified
on their own. The project name and make target have not been renamed.

```sh
make -C boards/hc1200-microcomp diamond \
  DIAMOND_HOME=/home/sash/.local/lscc/diamond/3.14
```

Other complete scripted builds:

```sh
make -C boards j11-diamond DIAMOND_HOME=/home/sash/.local/lscc/diamond/3.14
make -C boards j11-v2-diamond DIAMOND_HOME=/home/sash/.local/lscc/diamond/3.14
make -C boards/hc1200-microcomp diag-diamond DIAMOND_HOME=/home/sash/.local/lscc/diamond/3.14
make -C boards/hc1200-microcomp boot-trace-diamond DIAMOND_HOME=/home/sash/.local/lscc/diamond/3.14
```

These Tcl scripts run Synthesis → Translate → Map → PAR → PARTrace →
Jedecgen. They reject a missing timing summary or nonzero cumulative
negative slack before exporting. The process must exit zero. The original
board has a preparation target but no dedicated full-build Tcl target; use
its GUI project. Do not use the SD `diamond` target as an original build.

| Configuration | JED output |
|---|---|
| Legacy (GUI export) | `impl1-original/microcomp-original_impl1.jed` |
| Preserved `j11` | `impl1-j11/microcomp-j11_impl1.jed` |
| Specialized, no disk | `impl1-ucode/microcomp-ucode_impl1.jed` |
| Normal SD boot | `impl1-sdboot/microcomp_impl1.jed` |
| Native diagnostic | `impl1-diag/microcomp-diag_impl1.jed` |
| Boot trace | `impl1-boot-trace/microcomp-boot-trace_impl1.jed` |

The separate `make -C boards disk-diamond` / `disk-nofis-diamond` targets
select `microcomp-sd.ldf` / `microcomp-sd-nofis.ldf`, with implementation
directories `impl1-sd` / `impl1-sd-nofis`. They deliberately **stop after
PARTrace and do not export a JED**. `boards/Makefile.disk` remains a
compatibility entry point; the image rules are in `boards/sd.mk`.

Before claiming a fit, inspect `.mrp` (resources), `.par` (routing), `.twr`
(setup/hold), `.pad` (actual pins/pulls), and `.bgn` (configuration export).
Internal timing closure does not certify external SPI timing. For the exact
accepted source, hashes and remaining warnings, see
[HC1200 SD Diamond acceptance](hc1200-sd-diamond.md).

## Programming with FT2232

Programming is a separate, intentionally destructive step: it replaces the
FPGA configuration flash. Keep the previous working JED and use the exact
new file. The SD card is not written by the Programmer; the guest running
after configuration can write it.

### Linux access and channels

Use `lsusb -d 0403:6010` to find the current bus/device numbers, then inspect
that node, for example `ls -l /dev/bus/usb/001/013`. The numbers change after
replugging. USB programming access and `/dev/ttyUSB*` UART access are separate.

The development host used a rule for VID/PID `0403:6010`. Prefer a restricted
group rule such as this, with the user actually in `plugdev`:

```udev
SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="6010", MODE="0660", GROUP="plugdev"
```

After installing/changing a rule, reload with
`sudo udevadm control --reload-rules`, then replug the adapter. Reload alone
does not change permissions of an existing device node. Group changes also
need a new login session. The earlier `MODE="0666"` workaround grants all
local users access; it is not required if group/ACL access is correct.

Check `lsusb -t` and the sysfs interface bindings. On this setup channel A
is JTAG and channel B is the terminal UART. If `ftdi_sio` has claimed A,
release **only the identified A interface**, keeping B attached. Do not
globally `rmmod ftdi_sio`, unload USB-serial drivers or rewrite FTDI EEPROM
as a generic detection fix. Physical USB/sysfs paths are machine-specific.
Close only another application that actually owns the programming channel.

### Programmer configuration

The verified host has the standalone Programmer at
`/home/sash/.local/lscc/programmer/diamond/3.14`, separate from Diamond itself.
The official [Programmer package and manuals](https://www.latticesemi.com/programmer)
describe the tool. Installed 3.14 help for `pgrcmd` is under
`docs/webhelp/eng/Programmer/Command Line/`.

1. Detect/select **HW-USBN-2B (FTDI)**, port **FTUSB-0** on the verified host.
   With multiple adapters, resolve the intended cable first.
2. Scan the chain, then select the correct MachXO2-1200HC package manually
   if the scan cannot identify it. Expected ID is **0x012BA043**.
3. Use **FLASH Verify ID** as a read-only connection check. Do not bypass ID
   verification to work around an all-zero read. Check power, ground, JTAG
   wiring and JTAGENB instead. The board retains `JTAG_PORT=DISABLE`; its
   JTAGENB site is PT15C, QFN pin 26.
4. Select the exact new JED and **FLASH Erase,Program,Verify**. The accepted
   XCF used TCK delay 30; its log reports 200 kHz. A successful scan alone
   does not verify configuration flash.
5. Require successful program **and verify**, then inspect the UART at
   115200 8N1, no flow control. Transport diagnostics are available if SD
   boot remains silent; see [SD/FRAM diagnostics](hc1200-diagnostics.md).

Save XCF files for the chosen device, operation and artifact; do not reuse
an invalid/stale generated `impl1.xcf`. For CLI use, first create separate
`verify-id.xcf` and `program.xcf` in Programmer with those respective
operations. From their directory, the verified Linux invocation is:

```sh
# Read-only, provided verify-id.xcf selects FLASH Verify ID.
LD_PRELOAD=/lib/x86_64-linux-gnu/libstdc++.so.6 \
  /home/sash/.local/lscc/programmer/diamond/3.14/bin/lin64/pgrcmd \
  -infile verify-id.xcf -logfile verify-id.log -cabletype usb2 -portaddress FTUSB-0

# REPLACES FPGA FLASH: run only when ready to program the selected JED.
LD_PRELOAD=/lib/x86_64-linux-gnu/libstdc++.so.6 \
  /home/sash/.local/lscc/programmer/diamond/3.14/bin/lin64/pgrcmd \
  -infile program.xcf -logfile program.log -cabletype usb2 -portaddress FTUSB-0
```

The operation comes from the XCF, not its filename. Check the command exit
status and log. The accepted `a985039` JED completed erase/program/verify
in 19 seconds, followed by the user's successful RT-11 boot.

## Troubleshooting by stage

| Symptom | Check |
|---|---|
| `scuba: not found` under old `/usr/local/diamond/3.11...` | Current checkout and `DIAMOND_HOME`; use the board-specific target, not an old hard-coded build command |
| Synplify exits 1 | First actual error in synthesis output / `.srr`, license and runtime-library environment; a final return code is not a diagnosis |
| MAP says design does not fit | `.mrp`, selected top/ROM and complete source set; synthesis alone is not a fit check |
| LPF cannot find active UART/reset/SD ports | Wrong top/project, stale intermediate netlist or incompatible source/LPF combination |
| `libdvmapp.so` cannot load `libusb-0.1.so.4` | Install the distribution's compatible **legacy libusb-0.1 runtime** for the tool architecture; libusb-1.0 is not a drop-in SONAME replacement |
| Cable not detected | USB node permissions, interface-A ownership, other cable users and Programmer runtime dependencies |
| ID reads zero / flash verify fails | Power, JTAGENB, wiring, cable choice and clock; preserve the detailed Programmer log before retrying |
| JED succeeds but terminal is silent | Selected image, UART wiring/settings, SD raw-image layout; use diagnostic firmware rather than assuming a CPU fault |

The accepted SD build still has known unused-keyboard and configuration/EBR
warnings. Compare with the [recorded report](hc1200-sd-diamond.md); do not
treat every missing-port warning as harmless just because another one was.

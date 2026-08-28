# HC1200 microcomp: preserved J-11 hardware

[Legacy microcomp](hc1200-microcomp.md) · [CPU / firmware](fpga-j11.md) ·
[Specialized / SD microcomp](hc1200-microcomp-ucode.md) · [Diamond](diamond.md)

This is an alternative FPGA configuration of the same HC1200 board, not a
different PCB. It uses the preserved `--cpu j11` engine, not `rtl/cpu.v` and
not the newer `ucode` engine. It has no SD controller or SD bootstrap.

| Item | Selected source / value |
|---|---|
| FPGA | LCMXO2-1200HC-4SG32C, QFN32 |
| Diamond project | `boards/hc1200-microcomp/microcomp-j11.ldf` |
| Top module | `j11_hc1200_microcomp` in `j11_microcomp.v` |
| Native CPU | `rtl/j11_microengine.v` |
| Firmware | `ucode/j11.asm`, assembled with `--cpu j11` |
| Generated memory | `j11_ucode.mem`, `j11_urom_ebr.v` |
| Constraints / strategy | `j11.lpf` / `j11.sty` |
| Output JED | `impl1-j11/microcomp-j11_impl1.jed` |

All board-relative filenames above are under `boards/hc1200-microcomp/`.
This project is independent of `microcomp-original.ldf` and the current
default SD-boot `microcomp.ldf`.

## Build and test

From the repository root:

```sh
# Mac or Linux: assemble firmware and pack seven EBRs, no Diamond required.
make -C boards j11-ucode

# Ubuntu / Diamond: synthesis, MAP, PAR, setup/hold TRACE and JED export.
make -C boards j11-diamond DIAMOND_HOME=/home/sash/.local/lscc/diamond/3.14

# Icarus regression of the preserved implementation.
make -C testbench j11-test j11-core-banks-test j11-nofis-test
```

For the GUI, generate the image first, then open `microcomp-j11.ldf`.
The build never programs a device. Simulator dependencies and optional vendor
EBR models are covered in the [testbench guide](../testbench/README.md).

## Hardware behavior

The internal clock is 26.6 MHz. The FRAM pins (`gpio_mcs`, `gpio_msck`,
`gpio_mosi`, `gpio_miso`) belong to `spi_fram_guest_ram`, not software GPIO.
SPI FRAM SCK is about 6.65 MHz with the default divider. Guest RAM occupies
56 KiB of the board's physical 128 KiB. Microcode/context occupy seven EBRs:
3463 code + 64 context + 57 free words.

The UART is a microcoded DL11 console, 115200 8N1, using RX PT15D and TX PT17D.
Unlike the active `ucode` board's 50-Hz source, this preserved top retains
`TICK_DIVISOR=443333`, approximately **60 Hz**. It also retains MAINT=0 and
the old zero-read/ignored-write MMU stubs. Do not transfer the active image's
RT-11 identification or boot results to this reference configuration.

The four generic GPIO ports are high impedance; display outputs are held
safe/blanked. There is no guest mapping for them. Reset starts guest fetch
from FRAM; this configuration does not install guest code, read SD or provide
a terminal ODT. The guest must already be supplied, as the testbenches do.

The preserved checkpoint passed Diamond at 26.6 MHz: 1085 LUT4, 544 slices,
378 registers and seven EBRs (TRACE estimate 34.204 MHz). That checkpoint is
build/simulation evidence, not the later SD firmware's physical-board boot.
Full details are in the [reference engine report](fpga-j11.md#hc1200-shared-codecontext-ram-checkpoint-2026-08-28).

# HC1200 SD autoboot: Diamond acceptance

On 2026-08-28, source commit **`6668a85f85fa63a42b2aa4ec53533c83a83f5ecc`**
passed Synplify, Translate, MAP, PAR, setup/hold TRACE and JED export in
**Diamond 3.14.0.75.2** on Ubuntu. This is the main `microcomp.ldf` project,
top `ucode_sd_microcomp`, device **LCMXO2-1200HC-4SG32C**: J-11 without MMU,
EIS + FIS, 50-Hz clock and SD power-on bootstrap.

The build used a fresh `git archive` in
`/tmp/microcpu-sdboot-6668a85.admire`, not the Ubuntu working tree (which had
an unrelated strategy edit). The assembler and EBR image were rebuilt there:

```sh
make -C boards/hc1200-microcomp diamond \
  DIAMOND_HOME=/home/sash/.local/lscc/diamond/3.14
```

Exit status was zero. No RTL, assembly, LPF or strategy changes were needed
for this run. No board was programmed and no SD card was written.

## Resources and internal timing

| Resource | Used | Available | Remaining |
|---|---:|---:|---:|
| LUT4 | 1095 | 1280 | 185 |
| Slices | 548 | 640 | 92 |
| Registers | 431 | 1346 | 915 |
| EBR | 7 | 7 | 0 |
| Bonded PIO, including JTAGENB | 18 | 22 | 4 |

The four unused bonded pins are the original keyboard rows, not spare
unconnected board signals. uROM remains **3497 code + 64 context + 23 free
words = 3584 words**. BITGEN reports CFG mode and zero initialized UFM pages.

- Clock constraint: **26.600 MHz**; TRACE maximum: **37.627 MHz**.
- Worst setup slack: **+11.017 ns**; hold slack: **+0.289 ns**.
- **0 setup / 0 hold errors**, cumulative negative slack zero.
- **0 unrouted connections**; **17/17 active I/O pins locked**.

The clock constraint is present in the generated Synplify LPF and final PRF;
the original board pin LPF was not extended to add it. TRACE reports zero
unconstrained clock-domain paths, but **3 input-setup and 9 clock-to-output
paths remain unconstrained**. This is internal timing closure, not external
SD/FRAM timing acceptance or proof of operation at 37.627 MHz on the board.

## Implemented pins and pull modes

The final PAD report, not just the input LPF, confirms:

| Signal | Site | QFN pin | Pull |
|---|---|---:|---|
| UART RX | PT15D | 25 | none |
| UART TX | PT17D | 23 | none |
| SD CS | PL9B | 5 | none |
| SD MOSI | PR5C | 21 | none |
| SD SCLK | PT12D | 27 | none |
| SD MISO | PT12C | 28 | none |
| Reset | PL9A | 4 | up |

FRAM and display pins retain their original locations and no pulls. The
unused keyboard inputs are optimized away, producing missing-port/IOBUF
warnings; the PAD report nevertheless shows their physical sites PT11D,
PT11C, PT10D and PT10C as **unused, PULL:DOWN**. No extra generic GPIO ports
are placed. `sd.lpf` differs from `microcomp.lpf` only by renaming GPIO 0..3.

## Warnings and remaining hardware checks

This is a successful build **with warnings**, not a warning-free signoff.

- The original **JTAG_PORT=DISABLE** policy is unchanged. Diamond warns
  about disabled configuration ports; programming/recovery requires the
  board's proper **JTAGENB** arrangement (reserved site PT15C, pin 26).
- The seven initialized EBR banks trigger the six-pattern warning for
  **CFG_EBRUFM**. The actual exported configuration is **CFG**, not that mode.
- Diamond also warns about preloaded EBR wake-up with GSR disabled for the
  EBRs: chip/write enables must be inactive during wake-up. Physical power-on
  acceptance is still outstanding; RTL simulation does not certify wake-up.
- Synplify reports **BN161** multiple-driver warnings on intermediate nets,
  including the clock and inferred arithmetic. The same warning class is
  present in older builds; it was not suppressed here. Downstream routing
  and BITGEN DRC finish with zero errors, but this is not a post-route
  functional-equivalence test. Other warnings cover inferred clocks,
  unused signals and EDIF parameter properties.

## Artifacts and identity

The Ubuntu JED is
`/tmp/microcpu-sdboot-6668a85.admire/boards/hc1200-microcomp/impl1-sdboot/microcomp_impl1.jed`.
The build log and reports were copied to the Mac under the ignored directory
`testbench/build/diamond-sdboot-6668a85/`, preserving their board subdirectory.
It contains the JED, MAP/PAR/TRACE/PAD/PRF/Synplify/BITGEN/DRC reports, generated
clock LPF and the actual ROM/EBR sources used by Diamond.

All **25 checked RTL/assembly/build/constraint sources** match between hosts.
The generated ROM and EBR Verilog match byte-for-byte, and the ROM also
matches the image used by the Mac SD cold-boot/UART testbench.

| Artifact | SHA-256 |
|---|---|
| `j11_sd.mem` | `988397799b643e75985317c53b59b0f5f6e87479cf58acb6856bc97b32f23a41` |
| `sd_urom_ebr.v` | `3127d9c49e7ba65eceb242e097bbeb3018e4eb7acd46b0db81f2f38cbc7081c6` |
| `microcomp_impl1.jed` | `ed022204133c244ed86e3a889d166f8a580b2a8193727abd3b51f79b79d54c7f` |

Generated artifacts are not committed; this report records the exact tested
source commit. See [board instructions](hc1200-microcomp.md) and the separate
[RT-11 simulation acceptance](rt11-boot.md).

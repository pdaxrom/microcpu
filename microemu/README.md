# microemu

`microemu` is a C emulator for the `microcpu` core with selectable board
models.

`hc1200-mcu` is the default board model and uses the real board memory map:

- `0x0000..0x07ff`: zero-page SRAM
- `0x0800..0x17ff`: two SRAM pages
- `0xffe0..0xffe7`: UART, mirrored by `a0`
- `0xffe8..0xffef`: 15-bit GPIO
- `0xfff0..0xfff7`: timer

`hc1200-cpu` is a synthetic board model with 64 KiB RAM and the same UART,
GPIO, and timer peripherals mapped at `0xffe0..0xffff`. CPU accesses in that
MMIO range go to peripherals; image loading can still initialize the backing
RAM bytes there.

`hc1200-microcomp` models the MachXO2-1200 microcomp board:

- `0x0000..0x07ff`: permanent zero-page SRAM
- two 2 KiB SRAM windows selected by MMAP registers at `0xfff8..0xfffa`
- UART at `0xffe0..0xffe1`
- microcomp GPIO at `0xffe8..0xffef`
- timer at `0xfff0..0xfff2`
- 128 KiB SPI FRAM connected to the GPIO SPI pins

Display GPIO writes are stored but the display itself is not rendered.

The emulator is split into:

- `microcpu_core.c` / `microcpu_core.h`: CPU state, instruction decode, and
  execution through `read` / `write` / `intr` bus callbacks.
- `hc1200_mcu.c` / `hc1200_mcu.h`: the `hc1200-mcu` board wrapper, including
  SRAM, paged SRAM, UART, GPIO, and timer.
- `hc1200_cpu.c` / `hc1200_cpu.h`: the synthetic `hc1200-cpu` wrapper,
  including 64 KiB RAM with the `hc1200-mcu` peripherals overlaid at MMIO.
- `hc1200_microcomp.c` / `hc1200_microcomp.h`: the `hc1200-microcomp`
  wrapper, including MMAP page faults and bit-banged SPI FRAM.
- `microemu.c`: command-line interface and image loading.

Build:

```sh
make -C microemu
```

Build all assembler examples:

```sh
make -C microemu examples
```

Run the `Hello, World!` example:

```sh
make -C microemu run-hello
```

Equivalent explicit commands:

```sh
make -C asm microasm
asm/microasm -binary microemu/examples/hello_world.asm microemu/build/examples/hello_world.bin
microemu/microemu --format bin --stop-on-self-branch microemu/build/examples/hello_world.bin
```

Run the UART echo example with preloaded RX byte `A`:

```sh
make -C microemu run-echo
```

Equivalent explicit commands:

```sh
asm/microasm -binary microemu/examples/uart_echo.asm microemu/build/examples/uart_echo.bin
microemu/microemu --format bin --stop-on-self-branch --uart-rx "A" microemu/build/examples/uart_echo.bin
```

Run the synthetic 64 KiB RAM board smoke test:

```sh
make -C microemu run-ram64
```

Equivalent explicit commands:

```sh
asm/microasm -binary microemu/examples/ram64.asm microemu/build/examples/ram64.bin
microemu/microemu --board hc1200-cpu --format bin --stop-on-self-branch microemu/build/examples/ram64.bin
```

Run the `hc1200-microcomp` bootloader image:

```sh
make -C bootloader ../boards/sram.mem
microemu/microemu --board hc1200-microcomp --format auto --uart-rx "z" --max-steps 5000000 boards/sram.mem
```

The `boards/sram.mem` address-label format (`0000: ...`) is accepted by the
hex loader. Sending `z` enters serial bootloader mode and prints the bootloader
banner. The emulated SPI FRAM is used by the bootloader when it loads or saves
virtual memory pages.

Load and run a program through the `hc1200-microcomp` UART bootloader:

```sh
make -C asm microasm
python3 microemu/scripts/set_org.py --org 0x0800 \
  microemu/examples/calc_fis32.asm microemu/build/calc_fis32_0800.asm
asm/microasm -binary microemu/build/calc_fis32_0800.asm \
  microemu/build/calc_fis32_0800.bin
python3 microemu/scripts/boot_uart.py --start 0x0800 \
  --append-text "1.5 2 *\nq" \
  --output microemu/build/calc_fis32_boot.uart \
  microemu/build/calc_fis32_0800.bin
microemu/microemu --board hc1200-microcomp --format auto --stdin-rx \
  --stop-on-self-branch --max-steps 200000000 boards/sram.mem \
  < microemu/build/calc_fis32_boot.uart
```

The same preload stream can be passed without redirecting stdin:

```sh
microemu/microemu --board hc1200-microcomp --format auto \
  --uart-rx-file microemu/build/calc_fis32_boot.uart \
  --stop-on-self-branch --max-steps 200000000 boards/sram.mem
```

The shorter make target for the same FIS32 bootloader smoke test is:

```sh
make -C microemu run-boot-calc-fis32
```

For an interactive calculator session, generate a bootloader stream without
appended calculator input and let the emulator switch UART RX/TX to the
terminal after the preload bytes are consumed:

```sh
python3 microemu/scripts/boot_uart.py --start 0x0800 \
  --output microemu/build/calc_fis32_boot_interactive.uart \
  microemu/build/calc_fis32_0800.bin
microemu/microemu --board hc1200-microcomp --format auto \
  --uart-rx-file microemu/build/calc_fis32_boot_interactive.uart \
  --interactive-uart --stop-on-self-branch boards/sram.mem
```

The equivalent make target is:

```sh
make -C microemu run-boot-calc-fis32-interactive
```

In interactive mode `--max-steps` defaults to unlimited. Press `q` in the
calculator to halt normally, or `Ctrl-C` to interrupt the emulator and restore
the terminal. `--stdin-rx` cannot be combined with `--interactive-uart`; use
`--uart-rx-file` for the bootloader preload so stdin stays available for the
interactive UART.

Run the virtual-memory FRAM smoke test:

```sh
make -C microemu run-boot-fram-vm
```

This test loads `examples/fram_vm.asm` through the UART bootloader, writes
patterns to the normal virtual pages from `0x1000` through `0xf000`, evicts and
reloads them through the bootloader's memory-violation ISR, then jumps to a
routine on another virtual code page. It then overwrites and verifies every
byte of both 64 KiB FRAM banks through direct SPI, covering the full 128 KiB
device. Success prints `FRAM VM OK`; failures print `FRAM VM ERR` and stop the
emulator with an odd-PC error.

`set_org.py` only rewrites the first `org` directive in a generated source
copy. For normal `asm/examples` programs that already have the correct `org`,
skip that step and pass the matching address to `boot_uart.py --start`.
`boot_uart.py` emits the bootloader RX bytes: startup `z`, `L start end`, the
binary payload padded to 14-byte packets, optional `G`, and optional program
input from `--append-text` or `--append-hex`. Bootloader sync bytes are printed
on UART TX during loading, so raw emulator stdout contains binary noise before
the loaded program starts.

Run the 32-bit RPN calculator example:

```sh
make -C microemu run-calc
```

The integer calculator reads tokens from UART. Newline prints the signed
decimal value at the top of the stack and clears the expression; `q` halts for
emulator use.
Examples:

```text
12 34 +
-7 3 /
2 16 l
```

Run the FIS16 and FIS32 RPN calculator examples:

```sh
make -C microemu run-calc-fis16
make -C microemu run-calc-fis32
```

The floating-point calculators support `+`, `-`, `*`, `/` and decimal tokens
with an optional fractional part. FIS32 also accepts `e`/`E` decimal exponents,
for example:

```text
1.5 2 *
1 3 /
-2.25 4 +
0.111 1e6 /
```

FIS16 prints rounded 4 fractional digits; FIS32 prints up to 7 significant
digits, trims trailing fractional zeroes, and switches to scientific notation
for very small or large values. Floating overflow, decimal parse overflow, and
division by zero print `OVF` and reset the calculator stack.

Run arithmetic microbenchmarks:

```sh
make -C microemu bench
```

The benchmark runner generates temporary assembler programs under
`microemu/build/bench`, runs them on the synthetic `hc1200-cpu` board with
`--stats`, and prints estimated net instruction/cycle cost per operation after
subtracting the generated loop/setup baseline. The suite covers `int32.inc`
add/sub/mul/div/shifts plus FIS16 and FIS32 add/sub/mul/div.

Run a raw assembler binary:

```sh
microemu/microemu --format bin --stop-on-self-branch testbench/build/board_uart_smoke.bin
```

Run a Verilog `$readmemh`-style hex file:

```sh
microemu/microemu --format hex --stop-on-self-branch testbench/build/board_uart_smoke.hex
```

UART TX is written to stdout. UART RX can be preloaded with text or hex bytes:

```sh
microemu/microemu --uart-rx "100 2 /\nq" build/examples/calc32.bin
microemu/microemu --uart-rx "1.5 2 *\nq" build/examples/calc_fis16.bin
microemu/microemu --uart-rx "1.5 2 *\nq" build/examples/calc_fis32.bin
microemu/microemu --uart-rx-hex '4c 08 00 08 0e' bootloader.bin
microemu/microemu --uart-rx-file bootload.uart boards/sram.mem
```

`--uart-rx` supports common escapes: `\n`, `\r`, `\t`, `\\`, and `\xHH`.
`--interactive-uart` keeps preloaded RX bytes separate from terminal input:
UART TX is suppressed until that preload drains, then UART RX reads stdin
non-blockingly and UART TX writes stdout.

Useful diagnostics:

```sh
microemu/microemu --trace --dump-regs --stats --max-steps 2000 firmware.bin
```

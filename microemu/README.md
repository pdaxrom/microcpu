# microemu

`microemu` is a C emulator for the `microcpu` core with the `hc1200-mcu`
board memory map:

- `0x0000..0x07ff`: zero-page SRAM
- `0x0800..0x17ff`: two SRAM pages
- `0xffe0..0xffe7`: UART, mirrored by `a0`
- `0xffe8..0xffef`: 15-bit GPIO
- `0xfff0..0xfff7`: timer

The emulator is split into:

- `microcpu_core.c` / `microcpu_core.h`: CPU state, instruction decode, and
  execution through `read` / `write` / `intr` bus callbacks.
- `hc1200_mcu.c` / `hc1200_mcu.h`: the `hc1200-mcu` board wrapper, including
  SRAM, paged SRAM, UART, GPIO, and timer.
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
microemu/microemu --uart-rx-hex '4c 08 00 08 0e' bootloader.bin
```

Useful diagnostics:

```sh
microemu/microemu --trace --dump-regs --max-steps 2000 firmware.bin
```

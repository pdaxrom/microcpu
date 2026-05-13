# CPU Testbench

Run the CPU regression suite with:

```sh
make -C testbench test
```

The top-level shortcut is:

```sh
make test
```

The testbench builds assembly programs from `testbench/programs/`, loads them
into a behavioral 64 KiB memory with `$readmemh`, and exits through the
test-only status register at `$fffe`.

## Test-only MMIO

- `$fff4..$fff7`: expected read transaction queue
- `$fff8..$fffb`: expected write transaction queue
- `$fffc`: expected UART transmit byte
- `$fffd`: external interrupt trigger; `1` is immediate, values above `1`
  schedule a delayed interrupt
- `$fffe`: test status, `0` means pass and non-zero means fail code
- `$ffff`: character output

The harness also models the board MMIO blocks used by the programs:

- `$ffe0..$ffe1`: UART status/data
- `$ffe8..$ffeb`: GPIO data/direction
- `$fff0..$fff2`: timer counter/status

Bootloader smoke tests assemble `bootloader/bootldr-mcu.asm` and exercise the
banner, `S` save, `G` go, and `L` load command paths through the UART model.

## Board Smoke Tests

`make -C testbench board-smoke` compiles selected board top-levels with real
board UART/GPIO/timer modules and behavioral stubs for Lattice `OSCH`, `sram`,
and `srampages`.

- `board-mcu-smoke` loads `board_programs/board_uart_smoke.asm` into the
  `hc1200-mcu` zero-page SRAM and verifies a byte sent through the real UART.
- `board-mcu-bootload-rx` boots `bootloader/bootldr-mcu.asm` on the
  `hc1200-mcu` top-level, drives the board UART RX line with a load command,
  checks the written SRAM bytes, then jumps to the loaded payload.
- `board-microcomp-memmap` loads `board_programs/microcomp_memmap.asm` into the
  `hc1200-microcomp` zero-page SRAM and verifies memory page boundaries,
  memory-map interrupts for both remap slots, dirty flags, and UART pass byte.

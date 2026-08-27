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
- `j11-test` assembles the microengine firmware with `microasm` and guest
  PDP-11 programs under `j11_programs/` with `microasm11 --cpu dcj-11`. It
  covers FRAM transactions, the HC1200 I/O overlay and DL11, guest fetch,
  condition-code operations, all PDP-11 conditional branches, all addressing
  modes for `MOV` and `MOVB`, `CMP/CMPB`, `BIT/BITB`, `BIC/BICB`, `BIS/BISB`,
  `ADD`, `SUB`, `CLR/CLRB`, `COM/COMB`, `INC/INCB`, `DEC/DECB`, `NEG/NEGB`,
  `ADC/ADCB`, `SBC/SBCB`, `ROR/RORB`, `ROL/ROLB`, `ASR/ASRB`, `ASL/ASLB`,
  `TST/TSTB`, `SOB`, the software-trap
  group, and an assembled guest write to the physical DL11 UART. The
  double-operand test includes borrow, carry,
  signed-overflow, byte-width, and
  memory-destination/autoincrement cases. `bic_bis.asm` additionally verifies
  carry preservation, byte-register high-byte preservation, odd byte addresses,
  and byte/word autoincrement and autodecrement. `ea_timing.asm` verifies
  DCJ11 late register-source sampling after destination EA side effects for
  `MOV/MOVB`, `CMP/CMPB`, `BIT/BITB`, `ADD`, `SUB`, and PC-relative extensions. The
  `control_flow.asm` test covers `JMP`, `JSR`, and `RTS`, including DCJ11
  same-register EA timing, `JSR PC`, `RTS PC`, and the special `RTS SP` order.
  `control_traps.asm` verifies that register-direct `JSR` enters vector `010`
  without modifying the link register. The reserved-instruction test enters
  vector `010`, builds a guest stack frame in FRAM, runs a RAM handler, and
  returns via `RTI`; no RAM instruction emulator is installed. Separate
  assembled tests cover
  odd-word bus error vector `004`, `BPT/IOT/EMT/TRAP`, `SOB` flag preservation,
  `COM/COMB` byte and word EA behavior, `INC/INCB` and `DEC/DECB` boundary
  flags and all memory EA modes. `neg_adc_sbc.asm` verifies replacement of all
  four NZVC flags, carry-in zero and one, arithmetic boundaries, byte-register
  high-byte preservation, and memory side effects. `shift_rotate.asm` checks
  incoming and outgoing carry, `V = N xor C`, arithmetic sign fill, byte
  register preservation, and word/byte memory destinations. Tests also cover an
  externally supplied interrupt vector `060`. `irq_priority.asm` verifies that
  BR4 is deferred at PSW
  priority 4 while BR5 preempts it, and that a masked request remains latched.

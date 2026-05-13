# TODO

- Add coverage for `boards/hc1200/demo.v`, including its SRAM instantiation,
  address decode, and LED write path.
- Add coverage for `boards/hc1200-microcomp/gpio.v` side effects: SPI pins,
  display/control outputs, and key-row reads.
- Decide and document/fix reset behavior for CPU architectural registers that
  currently start as `X` in simulation.

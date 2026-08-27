# TODO

## J-11 V1: active plan (no MMU)

This is the agreed instruction milestone, not the complete J-11 architecture.
Work through the V1 acceptance checklist below. Do not start deferred features
automatically when it is complete.

### Constraints

- Base board: `boards/hc1200-microcomp`; 128 KiB SPI FRAM backs guest memory.
- No MMU or split I/D, one register set and one active SP.
- Implement instructions in `ucode/j11.asm`; no guest-RAM instruction emulator.
- Write guest tests in assembly and build them with `microasm11`.
- Run tests on the Mac; do not run Diamond until requested.
- Generate `boards/hc1200-microcomp/j11_ucode.mem` through `boards/Makefile`;
  do not commit generated images or build products.
- Commit each verified step. Increase uROM only if the in-scope work needs it.

### Priority instructions (agreed order)

These implementations and assembly tests already exist; do not implement them
again or interpret this checklist as authorization to add floating point.

- [x] 1. `XOR` — `8bc9c9e`; `testbench/j11_programs/xor.asm`.
- [x] 2. `MFPS`, `MTPS` — `8bc9c9e`; `testbench/j11_programs/psw.asm`.
- [x] 3. `MFPT`, `SPL` — `ad1064a`; `testbench/j11_programs/system.asm`.
- [x] 4. `WAIT`, `RESET`, `RTT` — `ad1064a`, `afb4e6e`;
  `testbench/j11_programs/{system,reset_rtt,trace_return}.asm`.
- [x] 5. `MARK` — `00097ce`;
  `testbench/j11_programs/{mark_lock,mark_edges}.asm`.
- [x] 6. `TSTSET`, `WRTLCK` — `00097ce`;
  `testbench/j11_programs/{mark_lock,lock_edges}.asm`.
- [x] 7. `MUL`, `DIV`, `ASH`, `ASHC` — `dbca9b8`, `af1b7c4`, `ed95350`,
  `85d8930`; `testbench/j11_programs/{mul,div,ash,ashc}.asm`.

### V1 acceptance: next work, in order

- [x] Audit the seven groups against the resident decoder, handlers, tests,
  and commit history.
- [x] Add MARK boundary tests for NN=0 and NN=63 (`MARK 077` in octal),
  including R5, SP, control flow, and unchanged NZVC.
- [x] Add lock-operation edge tests: TSTSET with an already-set low bit,
  WRTLCK zero/negative results and both carry states.
- [x] Explicitly test RESET flag preservation and the TRACE boundary after
  RTI versus RTT.
- [x] Run `make -C testbench -B j11-test` on the Mac and fix any regressions
  within this scope.
- [x] Check the uROM size and compare the generated board and testbench images.
- [x] Update this checklist with results and commit only the source changes.

Verification on 2026-08-27: `make -C testbench -B j11-test` passed all seven
simulation suites on the Mac, including the new assembly boundary tests.
Microcode remains 3280 bytes (1640 of 2048 words; 408 words free).
`testbench/build/j11_ucode.words` and the board's generated `j11_ucode.mem`
match byte for byte. No production RTL/microcode changes or Diamond runs were
needed for this acceptance step. Deferred work below remains deferred.

### Deferred: not part of V1 acceptance

- [ ] Banked stack pointers: KSP/SSP/USP, mode-switch save/restore and
  previous-mode SP access. Do this later; no bank switching has been added.
- [ ] Full `MFPI`, `MTPI`, `MFPD`, `MTPD` previous-mode/space semantics.
  A simplified unified-space implementation already exists (`3b2b03f`);
  extending it is deferred.
- [ ] `CSM` and the associated processor-mode/MMR3 behavior.
- [ ] MMU and split I/D spaces.
- [ ] FIS and FP11: excluded from this version, regardless of the real J-11's
  floating-point capabilities. No FP11 instructions have been implemented.
- [ ] CIS.
- [ ] SPI sequential-read buffering and differential testing against the C
  core: future candidates, not replacements for the agreed instruction plan.
- [ ] Diamond synthesis/place-and-route and physical-board verification:
  wait for a separate request.

The earlier PSW privilege work (`d2373b6`) and 32-word context expansion
(`ba424e8`) remain committed. They do not expand the active plan; do not roll
them back or build further mode/FP11 features on them without a new request.

## Other repository tasks (not active in the J-11 V1 plan)

- Add coverage for `boards/hc1200/demo.v`, including its SRAM instantiation,
  address decode, and LED write path.
- Add coverage for `boards/hc1200-microcomp/gpio.v` side effects: SPI pins,
  display/control outputs, and key-row reads.
- Decide and document/fix reset behavior for CPU architectural registers that
  currently start as `X` in simulation.

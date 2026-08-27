# TODO

## J-11 V1: active plan (no MMU)

This is the agreed instruction milestone, not the complete J-11 architecture.
The original V1 instruction milestone below is complete. The user-authorized
follow-up is recorded separately; do not infer authorization for other features.

### Constraints

- Base board: `boards/hc1200-microcomp`; 128 KiB SPI FRAM backs guest memory.
- No MMU or split I/D, one register set. The follow-up now adds banked SPs.
- Implement instructions in `ucode/j11.asm`; no guest-RAM instruction emulator.
- Keep J-11-specific register decoding, masks, PSW/CPUERR/PIRQ/STKLIM effects,
  and guest timer semantics in assembly microcode too. Do not add a J-11 MMIO
  state machine, register masks, or PSW side effects to `j11_microengine.v`.
  Any new physical time source/interface needs a separate hardware decision;
  an instruction-count clock is a simulation timebase, not a real 50/60 Hz clock.
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

### Active follow-up (requested after V1 acceptance)

- [x] Reuse `k1801vm1/tests/core_tests.c` for **J-11 only**, built with
  `ENABLE_MMU=0`, including EIS. Replay applicable fixtures on Verilog and
  reassemble guest instructions with `microasm11`; distinguish C and RTL results.
  Initial selected coverage: 187 snapshots, 29 EIS cases; not the entire suite.
- [x] Banked stack pointers: KSP/SSP/USP, trap/RTI/RTT mode-switch save/restore,
  and previous-mode SP access, with the corresponding core and assembly tests.
  `j11-core-banks-test`: 187/187 RTL snapshots pass, including 29 EIS cases.
  `sp_banks.asm` passes through SPI FRAM; uROM is now 1694/2048 words.
- [ ] J-11 processor-owned I/O registers: inventory the C-core map, implement
  defined reads/writes and side effects, and port register tests. This is
  separate from board UART/timer devices; MMU remains disabled.
  - [x] Inventory `core/core.c`: MEMERR, CCR, MAINT, HITMISS, CPUERR, PIRQ,
    STKLIM and PSW; disabled-MMU MMR/PAR/PDR stubs; optional reserved registers.
  - [x] Remove the uncommitted RTL MMIO experiment. Production Verilog remains
    identical to `3369b8f`; the register implementation is still pending.
  - [ ] Add shared microcoded word/byte access helpers, including indirect EA,
    stack, and instruction-fetch paths. Preserve live microengine registers and
    explicitly save arithmetic flags before helper calls where necessary.
  - [ ] Implement register reads/writes and side effects in those helpers;
    test byte lanes, read-only/write-clear behavior, explicit PSW writes and
    stack-bank switching, PIRQ arbitration, and CPUERR/STKLIM traps.
  - [ ] Replay corresponding J-11 C-core fixtures and add `microasm11` guest
    programs. Do not mark register support complete from C-only test results.
- [ ] LTC/KW11-L-compatible timer: `177546`, vector `100`, BR6. Implement guest
  CSR and interrupt semantics in microcode and test INIT, byte accesses,
  acknowledgement, masked priority, repeated ticks, and WAIT wakeup.
  - [x] Locate the C device in `k1801vm1/lsi11/dev_kw11.c` and inspect DEC
    KDJ11-B User's Guide section 1.9 / Table 1-23 (printed page 1-45).
  - [ ] Resolve/document the reference difference: KDJ11-B LCM clears on
    interrupt acknowledge or writing zero, whereas the current C model clears
    it on CSR-low-byte read and leaves it set on interrupt acknowledge.
    Use documented KDJ11-B behavior for the J-11 target; do not silently modify
    the reference C device or pretend these two models already agree.
  - [ ] Provide deterministic tick tests; document the physical timebase still
    needed for wall-clock timing, without adding timer-specific Verilog here.
- [ ] FIS (`FADD`, `FSUB`, `FMUL`, `FDIV`): add all four instructions with
  rounding/error tests if they fit the remaining current uROM after SP/I/O work.
  Do not confuse FIS with FP11 or silently enlarge the FIS budget.
- [ ] Full local regression and source-only commits for verified steps.

Architecture correction verified on 2026-08-27: after removing the uncommitted
RTL MMIO attempt, `make -C testbench j11-test j11-core-banks-test` passes all
seven J-11 suites and 187/187 reference snapshots (29 EIS). This verifies the
existing baseline only; CPU I/O and timer follow-up items remain open.

### Deferred: not part of the active follow-up

- [ ] Full `MFPI`, `MTPI`, `MFPD`, `MTPD` previous-mode/space semantics.
  A simplified unified-space implementation already exists (`3b2b03f`);
  banked-SP access is now active, but MMU/split-space semantics remain deferred.
- [ ] `CSM` and the associated processor-mode/MMR3 behavior.
- [ ] MMU and split I/D spaces.
- [ ] FP11: not requested; no FP11 instructions have been implemented.
- [ ] Alternate R0..R5 register sets (distinct from the now-requested SP banks).
- [ ] CIS.
- [ ] SPI sequential-read buffering and broader randomized differential tests:
  future candidates beyond the requested existing core tests.
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

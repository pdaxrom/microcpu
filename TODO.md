# TODO

## J-11 V1: active plan (no MMU)

This is the agreed instruction milestone, not the complete J-11 architecture.
The original V1 instruction milestone below is complete. The user-authorized
follow-up is recorded separately; do not infer authorization for other features.

### Constraints

- Base board: `boards/hc1200-microcomp`; 128 KiB SPI FRAM backs guest memory.
- No MMU or split I/D, one register set. The follow-up now adds banked SPs.
- Implement instructions in `ucode/j11.asm`; no guest-RAM instruction emulator.
- Keep J-11-specific register decoding, masks, PSW/CPUERR/PIRQ effects,
  and guest timer semantics in assembly microcode too. Do not add a J-11 MMIO
  state machine, register masks, or PSW side effects to `j11_microengine.v`.
  The user approved a raw UART/time-counter interface on 2026-08-27, without
  guest DL11/LTC address decoding or guest interrupt generation in the adapter.
  Native UART/time event notifications are also explicitly approved;
  an instruction-count clock is a simulation timebase, not a real 50/60 Hz clock.
- Write guest tests in assembly and build them with `microasm11`.
- Run tests on the Mac. Diamond is now approved for the uROM resource/fit check
  (2026-08-28), in an isolated copy without overwriting the Ubuntu worktree.
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
- [x] J-11 processor-owned I/O registers: inventory the C-core map, implement
  defined reads/writes and side effects, and port register tests. This is
  separate from board UART/timer devices; MMU remains disabled.
  - [x] Inventory `core/core.c`: MEMERR, CCR, MAINT, HITMISS, CPUERR, PIRQ,
    PSW; disabled-MMU MMR/PAR/PDR stubs; optional reserved registers.
    The C-only programmable STKLIM is not part of the DCJ11 target: implement
    the documented fixed kernel stack limit `0400`, with yellow/red traps.
  - [x] Remove the uncommitted RTL CPU-MMIO experiment. `cpu.v` and
    `j11_microengine.v` remained unchanged at that checkpoint; CPU register
    implementation is recorded below.
  - [x] Add shared microcoded word/byte access helpers, including indirect EA,
    stack, and instruction-fetch paths. Preserve live microengine registers and
    explicitly save arithmetic flags before helper calls where necessary.
  - [x] Implement register reads/writes and side effects in those helpers;
    test byte lanes, read-only/write-clear behavior, explicit PSW writes and
    stack-bank switching, PIRQ arbitration, and CPUERR/fixed-limit stack traps.
  - [x] Replay corresponding J-11 C-core fixtures and add `microasm11` guest
    programs. Do not mark register support complete from C-only test results.
    CPU I/O is in `j11_cpu_io.asm`, stack checking in `j11_stack.asm`; no new
    RISC opcode, context word, or J-11-specific RTL logic was added. Tests cover
    byte lanes, CCR masks, PSW/T/CC/bank effects, seven PIR levels and priority
    arbitration, sticky CPUERR, fixed-0400 yellow, RED recovery at 0/2, and
    raw-bus-fault NXM/double-abort behavior. CCR/PIRQ differences from the C
    model are documented; disabled-MMU registers are zero/ignore stubs only.
- [x] DL11 console in microcode: `177560..177566`, IE/DONE, RX/TX request
  latches, byte lanes, RE/RBUF acknowledgement, BREAK/maintenance loopback.
  Raw UART/time notifications skip hardware polling on event-free boundaries.
  Assembly tests cover ODT-style polling and real serial bytes; ODT itself,
  modem/error status and programmable baud-rate extensions remain future work.
  Current framing: 115200, 8N1 (Verilog `BAUD` parameter).
- [x] LTC/KW11-L-compatible timer: `177546`, vector `100`, BR6. Implement guest
  CSR and interrupt semantics in microcode and test INIT, byte accesses,
  acknowledgement, masked priority, repeated ticks, and WAIT wakeup.
  - [x] Locate the C device in `k1801vm1/lsi11/dev_kw11.c` and inspect DEC
    KDJ11-B User's Guide section 1.9 / Table 1-23 (printed page 1-45).
  - [x] Resolve/document the reference difference: KDJ11-B LCM clears on
    interrupt acknowledge or writing zero, whereas the current C model clears
    it on CSR-low-byte read and leaves it set on interrupt acknowledge.
    Use documented KDJ11-B behavior for the J-11 target; do not silently modify
    the reference C device or pretend these two models already agree.
  - [x] Provide deterministic tick tests, including wrap and repeated WAIT
    wakeups. The approved raw time counter advances independently of bus stalls
    and WAIT, nominally 60 Hz at 26.6 MHz. It has no guest timer CSR or IRQ vector.
  - [x] Verify equal-IPL masking, BR6 over BR4, RX over TX, request ACK versus
    DONE, IE re-arm, RESET flags/state, private-address isolation and odd words.
- [ ] FIS (`FADD`, `FSUB`, `FMUL`, `FDIV`): add all four instructions with
  rounding/error tests if they fit the remaining current uROM after SP/I/O work.
  Do not confuse FIS with FP11 or silently enlarge the FIS budget.
  - [x] Recheck budget after CPU/SP/I/O work: **3002/3072 words, 70 free**.
    Full FIS with normalization, rounding and arithmetic errors does not fit
    this remainder. It is not implemented; no partial arithmetic is claimed.
    `fis_unavailable.asm` checks all four opcodes still trap through `010`.
    The user now approved checking a larger uROM via distributed register RAM
    and Diamond. Reassess FIS after that fit check; ODT remains deferred.
- [ ] Move the 8x16 host and 32x16 context arrays to distributed RAM; check
  3584x16 uROM packing, total LUT/EBR use and timing on HC1200 in Diamond.
- [x] Full local regression and source-only checkpoint for CPU I/O/stack work.

Architecture correction verified on 2026-08-27: after removing the uncommitted
RTL MMIO attempt, `make -C testbench j11-test j11-core-banks-test` passes all
seven J-11 suites and 187/187 reference snapshots (29 EIS). This verifies the
existing baseline only; CPU I/O and timer follow-up items remain open.

UART/LTC follow-up verified on 2026-08-27: `make -C testbench j11-test
j11-core-banks-test` passes all eight J-11 simulation suites and 187/187
reference snapshots (29 EIS). The common memory dispatcher and devices occupy
2529/2560 uROM words. Generated board/testbench images match; no generated files
are committed. Diamond was not run: hardware fit/timing must be measured later.
CPU-owned I/O registers and fixed-`0400` yellow/red stack protection remain
the next step at that historical checkpoint; they are implemented below.

CPU I/O and stack follow-up (2026-08-28): 201 selected J-11 no-MMU C-core
snapshots (29 EIS) now compare CPUERR/PIRQ/CCR in addition to registers, SP
banks and RAM. New assembly programs exercise processor I/O and fixed-stack
semantics on the board/FRAM path. The simulated uROM grew from 2560 to 3072
words for this CPU work, with 3002 occupied; the remaining 70 words do not fit
FIS. The old mapping would need nine EBRs including the register files, beyond
the seven available: hardware fit requires the RAM placement work above.
FIS and ODT remain unimplemented, explicitly rather than accidentally omitted.
`make -C testbench j11-test j11-core-banks-test` passes all nine simulation
suites and 201/201 reference snapshots (29 EIS). Board/testbench uROM images
match. Legacy PSW/privileged/MARK test stacks were moved or restored above
0400; explicit stack-fault tests still exercise the protected region.

### Deferred: not part of the active follow-up

- [ ] Full `MFPI`, `MTPI`, `MFPD`, `MTPD` previous-mode/space semantics.
  A simplified unified-space implementation already exists (`3b2b03f`);
  banked-SP access is now active, but MMU/split-space semantics remain deferred.
- [ ] `CSM` and the associated processor-mode/MMR3 behavior.
- [ ] MMU and split I/D spaces.
- [ ] FP11: not requested; no FP11 instructions have been implemented.
- [ ] ODT console/monitor: explicitly postponed by the user; DL11-compatible
  polling and serial framing are ready, but ODT itself is not implemented.
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

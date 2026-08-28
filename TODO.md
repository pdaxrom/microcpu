# TODO

## J-11 V1: active plan (no MMU)

This is the agreed instruction milestone, not the complete J-11 architecture.
The original V1 instruction milestone below is complete. The user-authorized
follow-up is recorded separately; do not infer authorization for other features.

### Constraints

- Base board: `boards/hc1200-microcomp`; 128 KiB SPI FRAM backs guest memory.
- No MMU or split I/D; banked SPs and the newly requested two R0..R5 sets.
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
- [x] FIS (`FADD`, `FSUB`, `FMUL`, `FDIV`): add all four instructions with
  rounding/error tests if they fit the remaining current uROM after SP/I/O work.
  Do not confuse FIS with FP11 or silently enlarge the FIS budget.
  - [x] Recheck budget after CPU/SP/I/O work: **3002/3072 words, 70 free**.
    Full FIS with normalization, rounding and arithmetic errors does not fit
    this remainder. It is not implemented; no partial arithmetic is claimed.
    `fis_unavailable.asm` checks all four opcodes still trap through `010`.
  - [x] Approved uROM expansion fits Diamond: **3002/3584 words, 582 free**.
  - [x] Reassess all four instructions against the recovered 582 words:
    **389 additional words**, **3391/3584 occupied**, **193 free**. All four
    are resident in `ucode/j11_fis.asm`; no production RTL or capacity change.
    Integer register-pair arithmetic covers the full DEC exponent range,
    normalization, nearest/ties-away rounding, clean/dirty zero and `0244`
    arithmetic errors. FIS is a compatibility extension, not FP11 or a
    guard-bit-exact KE11-F hardware clone; details are in `docs/fpga-j11.md`.
  - [x] Add microasm11 guest tests for arithmetic/rounding/errors, R0..R7,
    user SP and trap frames, TRACE, reserved/odd cases, and partial bus faults.
    Use an independent exact rational oracle instead of the C host-float FIS
    path. The diagnostic profile `J11_DISABLE_FIS` retains reserved opcodes.
  - [x] Final Mac verification (2026-08-28): **4040/4040** FIS reference
    cases, the full `j11-test` suite, and **201/201** no-MMU core snapshots.
    The actual seven-bank EBR model passes all 3584 ROM words, assembled
    instruction/CPU/FIS tests, and the same 201/201 snapshots (29 EIS).
    `j11-nofis-test` also passes. Board/testbench images match; no Diamond
    rerun, device programming or generated-file commit was performed.
- [x] Move the 8x16 host and 32x16 context arrays to distributed RAM; check
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

HC1200 uROM fit check (2026-08-28): the generated ROM uses seven explicit
512x18 EBRs, and both small register arrays use distributed RAM. A shared
native ADD/SUB/SUBB datapath saves the final 20 LUTs without adding an opcode
or changing microinstruction cycles. Diamond 3.14 completes PAR and JED:
1279/1280 LUTs, 640/640 slices, 7/7 EBRs, 462/1346 registers. Internal timing
passes at 26.6 MHz (30.443 MHz reported maximum, setup +4.746 ns, hold +0.289 ns).
The 3584-word uROM has 582 words free, but fabric is effectively full.
No board programming was performed; external I/O delays remain unverified.
Final Mac verification passes all ten simulation suites plus three ROM-packer
unit tests, 82,163 native ALU checks and 201/201 C-core snapshots (29 EIS).
The generated EBR ROM also passes all 3584 word/enable checks, the assembled
instruction and CPU-I/O suites, and the same 201/201 C-core snapshots using
Lattice's simulation models.

### RISC area reduction and SD feasibility (requested 2026-08-28)

- [x] Audit the actual J-11 microengine, not the ordinary `cpu.v` that this
  board configuration does not instantiate.
- [x] Share native address/ALU arithmetic and relative-PC arithmetic; reuse
  stable instruction/PC and operand registers without changing ISA or cycles.
- [x] Narrow the FRAM SPI divider to its reachable range; test dividers
  1, 2, 3, 5 and 17, including individual clock phases.
- [x] Verify 115,255 ALU/address cases, 109,360 PC cases and 900 timed shifts;
  expand the native assembly smoke test for byte writes and memory-loaded PC.
  All twelve Mac suites and 201/201 J-11 C-core snapshots (29 EIS) pass.
- [x] Measure the complete board in Diamond: **1138/1280 LUTs**, 571/640 slices,
  377/1346 registers and 7/7 EBRs. This saves 141 LUTs and 85 registers versus
  `0522437`, leaving **142 LUTs**. Timing passes at 26.6 MHz, maximum 28.103 MHz,
  setup +2.011 ns and hold +0.289 ns. External I/O timing is still unverified.
- [x] Repeat the final guest/core tests through the actual EBR model:
  all 3584 ROM words, the guest instruction/CPU-I/O suites and 201/201
  C-core snapshots (29 EIS) pass. Commit only the verified source changes.
- [ ] Confirm SD wiring and guest-visible disk-controller type before its
  implementation. Evaluate separate-SPI streaming into FRAM with a small
  FIFO: no EBR sector buffer is available while retaining the 3584-word uROM.
  Do not claim the entire disk controller fits from the RISC saving alone.

At that RISC checkpoint the microcode was **3002/3584 words**. The subsequent
FIS fit check adds 389 words, for **3391/3584 words** and **193 free**. ODT
remains deferred. No disk controller or SD access has been implemented and
no board programming was performed.

### Register sets and console HALT (requested 2026-08-28)

- [x] Verify PSW.RS and console HALT/Proceed against DCJ11 UG sections 1.5,
  5.3.2–5.3.4; do not copy the C HALT placeholder or K1801VM2 H-mode.
- [x] Extend only generic context storage/indexing to 64 words; no J-11 bank
  selection, PSW masks or HALT state machine in RTL. Keep 3584-word uROM.
- [x] Swap active/inactive R0..R5 in microcode on effective PSW.RS changes:
  explicit byte/word writes, trap/IRQ and protected RTI/RTT; SP/PC stay separate.
- [x] Console stop retains PC/PSW/banks, performs no guest bus accesses and
  cannot be woken by IRQ. Private firmware HALT/Proceed mailbox supports one
  instruction before events and held-request stepping, including WAIT/TRACE.
  The mailbox is groundwork for ODT, not an external pin or guest register.
- [x] Add microasm11 register/privileged-HALT/console tests; expand C replay
  to 209 snapshots (29 EIS), including inactive R0..R5 state where valid.
  Explicitly account for C's lazy bank initialization only in fixture seeding.
- [x] Diamond fit in an isolated Ubuntu copy: 1213/1280 LUT, 609/640 slices,
  378/1346 registers, 7/7 EBR; 26.6 MHz passes (maximum 27.715 MHz,
  setup +1.513 ns, hold +0.289 ns). No board programming or pin changes.
- [x] Final Mac regression and 209/209 no-MMU snapshots (29 EIS); all 4040
  exact-reference FIS cases pass. The real seven-bank Lattice ROM passes all
  3584 word/enable checks, guest/CPU/FIS/RS/HALT programs, and 209/209 snapshots.
  The extra HALT vector-priority test also passes on that ROM. Diamond/local
  ROM words agree (only `od` whitespace differs); commit source files only.

At that checkpoint: **3463/3584 words, 121 free**, including FIS. The two sets
and console groundwork use 72 words beyond the FIS checkpoint. Fabric has
67 LUTs free; this is not a guarantee that a full SD controller will fit.

### Shared microcode/context RAM (requested 2026-08-28)

- [x] Preserve the register-set/HALT baseline (`895ec88`) before changing
  storage. Leave unrelated untracked and generated files out of commits.
- [x] Move the 64-word context into the last 64 words of the same seven EBRs
  as microcode; keep only eight native working registers in distributed RAM.
  Keep register banks, PSW, stack and HALT behavior in assembly. Guest stack
  contents stay in SPI FRAM; SP values and fixed helper frames live in context.
- [x] Restrict the hardware write port to context; latch uIR while reading
  native operand A, then reuse the read port for context. No added opcode or
  instruction cycle: ordinary native instructions still take six clocks.
- [x] Reserve 64 words in both Makefiles and the common image packer. Reject
  overlapping code, initialize context to zero and clear only context on reset.
  Current layout: **3463 code + 64 context + 57 free = 3584 words**.
- [x] Add an assembled native memory test (35,808 six-clock instructions),
  index/PC/boundary/reset checks, and real EBR write/read/enable tests. Observe
  actual shared memory in guest tests rather than retaining a shadow in RTL.
- [x] Diamond 3.14 in an isolated copy: **1085/1280 LUTs**, 544/640 slices,
  378/1346 registers, 7/7 EBR. Saves **128 LUTs / 65 slices** versus `895ec88`;
  distributed RAM drops 120 -> 24 LUTs, total free fabric is **195 LUTs**.
  Internal 26.6 MHz timing passes: maximum 34.204 MHz, setup +8.358 ns,
  hold +0.289 ns. RTL and `.mem` hashes match Mac; no board programming.
- [x] Full Mac `j11-test`, `j11-core-banks-test` and `j11-nofis-test` pass;
  **209/209** no-MMU snapshots (29 EIS) and **4040/4040** exact FIS cases.
  `j11-ebr-test` passes the port/reset and native boundary tests, all selected
  guest/CPU/FIS/RS/HALT programs, and the same **209/209** snapshots. Record
  the measured result and commit only source files; generated images ignored.

### Specialized ucode engine: five-stage plan (approved 2026-08-28)

Keep `original` and the `j11` RTL/firmware at the `d4dabf1` reference unchanged.
Only the independent `ucode` profile and `ucode/v2/` evolve. Commit each stage
after verification; never commit generated images or program the board.

- [x] 1. Preserve three assembler/RTL profiles and record the first measured
  ucode checkpoint: 3317 code + 64 context + 203 free words; 964/1280 LUTs,
  483/640 slices, 7/7 EBRs, 41.432 MHz TRACE maximum at 26.6 MHz constraints.
  All native/guest regressions, 209 core snapshots, 4040 FIS cases and real-EBR
  tests pass. Diamond synthesis through JED passes; external I/O is unverified.
- [x] 2. Compact native CALL/JMP/RET and context-RAM nested returns: 2968
  code words (-349), 1013 LUTs (+49), 510 slices, 385 registers, 7 EBRs;
  TRACE 48.195 MHz. Assembler 11 smoke + 20 profile tests, native/guest tests,
  209 core snapshots, 4040 exact FIS cases and actual-EBR regression pass.
  Diamond through JED passes with no setup/hold violations at 26.6 MHz.
- [ ] 3. Evaluate word-addressed uPC and native carry/borrow arithmetic
  independently. Retain only measured improvements; verify and commit the
  implementation or a documented negative experiment.
- [ ] 4. Full preserved/new CPU, guest/core/FIS and actual-EBR regression;
  isolated Diamond measurements and reproducible acceptance checks. Commit.
- [ ] 5. Isolated SD/FRAM disk prototype for the already selected RK611/RH11
  controller at octal 0177440, using `k1801vm1/lsi11/dev_rh11.c` as reference.
  Measure complete-board fit, test reads/writes, transfer arbitration and
  error paths; do not infer fit from CPU savings. No sector EBR is available.
  SD pin assignment and physical writes require confirmation; simulation
  and a separate synthesis top must not change the production board wiring.

The controller type is already chosen by the user; earlier entries calling
it undecided are historical. ODT, MMU/split I/D and FP11 remain deferred.

### Deferred: not part of the active follow-up

- [ ] Full `MFPI`, `MTPI`, `MFPD`, `MTPD` previous-mode/space semantics.
  A simplified unified-space implementation already exists (`3b2b03f`);
  banked-SP access is now active, but MMU/split-space semantics remain deferred.
- [ ] `CSM` and the associated processor-mode/MMR3 behavior.
- [ ] MMU and split I/D spaces.
- [ ] FP11: not requested; no FP11 instructions have been implemented.
- [ ] ODT console/monitor: explicitly postponed by the user; DL11-compatible
  polling and serial framing are ready, but ODT itself is not implemented.
- [ ] ODT front end / board HALT request source and fatal double-abort recovery.
  Console execution state is implemented above; no UART command parser yet.
- [ ] CIS.
- [ ] SPI sequential-read buffering and broader randomized differential tests:
  future candidates beyond the requested existing core tests.
- [ ] Physical-board UART/FRAM verification and external I/O timing constraints:
  wait for a separate request; Diamond resource/internal-timing checks are done.

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

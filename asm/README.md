Documentation

Full assembler and ISA reference (including RTL semantics): docs/isa.md

Include files

- include/pseudo.inc: common pseudo-instruction macros.
- include/devmap.inc: board/device address constants.
- include/int32.inc: 32-bit arithmetic procedures. It emits code, so include it
  after the calling code or branch around it. Values use v1:v0 as lhs/result
  and v3:v2 as rhs.
- include/fis.inc / include/fis16.inc: FIS16 floating point procedures
  (`fadd`, `fsub`, `fmul`, `fdiv`). It emits code and includes int32.inc
  internally. Routines use stack frames for scratch state and are reentrant.
- include/fis32.inc: 32-bit FIS-like floating point procedures (`f32add`,
  `f32sub`, `f32mul`, `f32div`) using sign + excess-0200 exponent + 23-bit
  fraction. It emits code, includes int32.inc internally, and is reentrant.

Testing

Run assembler smoke tests:

sh scripts/test-asm-smoke.sh

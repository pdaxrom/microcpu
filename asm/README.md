Documentation

Full assembler and ISA reference (including RTL semantics): docs/isa.md

Include files

- include/pseudo.inc: common pseudo-instruction macros.
- include/devmap.inc: board/device address constants.
- include/int32.inc: 32-bit arithmetic procedures. It emits code, so include it
  after the calling code or branch around it. Values use v1:v0 as lhs/result
  and v3:v2 as rhs.

Testing

Run assembler smoke tests:

sh scripts/test-asm-smoke.sh

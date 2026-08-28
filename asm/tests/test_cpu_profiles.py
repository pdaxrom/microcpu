#!/usr/bin/env python3
"""CPU profiles: encoding, rejected instructions, object tags and disassembly."""
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import unittest

ASM_DIR = Path(__file__).resolve().parents[1]
PROFILES = ("original", "j11", "ucode")


class CpuProfiles(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="microasm-cpu-")
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.serial = 0

    def run_tool(self, tool, *args, ok=True):
        result = subprocess.run([str(ASM_DIR / tool), *map(str, args)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def assemble(self, source, cpu=None, object_file=False, ok=True, extra=()):
        self.serial += 1
        inp = self.directory / f"test{self.serial}.asm"
        out = inp.with_suffix(".obj" if object_file else ".bin")
        inp.write_text(source)
        options = [] if cpu is None else ["--cpu", cpu]
        log = self.run_tool("microasm", *options,
                            "-object" if object_file else "-binary",
                            *extra, inp, out, ok=ok)
        if ok:
            self.assertTrue(out.exists(), log)
        else:
            self.assertFalse(out.exists(), log)
        return out, log

    def test_default_and_common_encoding(self):
        source = "setl v0, $34\nseth v0, $12\nadd v1, v0, 3\nb *\n"
        paths = [self.assemble(source, cpu)[0] for cpu in (None, *PROFILES)]
        for path in paths:
            self.assertEqual(path.read_bytes(), bytes.fromhex("433453128c67b000"))

    def test_profile_encodings(self):
        cases = {
            "original": ("sws\nswu\nsetp v0\ngetp v1\nmovl v0, v1\n",
                         "9000a000c300d4006380"),
            "j11": ("gget pc, 0\ngset pc, 0\ngget v0, 31\ngset v1, 16\n"
                    "ggetr v0, pc\ngsetr v1, v2\ngetf v0\n",
                    "9000a000931fa410c300d4a0e300"),
            "ucode": ("ldi8 v0, $ff\ngget v0, 32\ngset v1, 63\n"
                      "ggetr pc, v0\ngsetr pc, v1\n",
                      "63ff9320a43fc060d080")
        }
        for cpu, (source, expected) in cases.items():
            with self.subTest(cpu=cpu):
                out, _ = self.assemble(source, cpu)
                self.assertEqual(out.read_bytes(), bytes.fromhex(expected))

    def test_unsupported_instructions(self):
        unsupported = {
            "original": ("gget v0, 0", "gset v0, 0", "ggetr v0, v1",
                         "gsetr v0, v1", "getf v0", "subb v0, v1, v2", "ldi8 v0, 0"),
            "j11": ("sws", "swu", "setp v0", "getp v0", "ldi8 v0, 0"),
            "ucode": ("sws", "swu", "setp v0", "getp v0", "movl v0, v1", "movh v0, v1")
        }
        for cpu, instructions in unsupported.items():
            for instruction in instructions:
                with self.subTest(cpu=cpu, instruction=instruction):
                    _, log = self.assemble(instruction + "\n", cpu, ok=False)
                    self.assertIn("not supported", log)

    def test_macro_cannot_bypass_profile(self):
        for cpu in ("original", "j11"):
            self.assemble("macro wrong\nldi8 v0, 1\nendm\nwrong\n", cpu, ok=False)
        self.assemble("if 0\nldi8 v0, 999\nendif\nb *\n", "original")

    def test_source_cpu_assertion(self):
        for cpu in PROFILES:
            self.assemble(f"cpu {cpu}\nb *\n", cpu)
            for other in set(PROFILES) - {cpu}:
                self.assemble(f"cpu {cpu}\nb *\n", other, ok=False)
        self.assemble("cpu imaginary\n", "original", ok=False)

    def test_cpu_symbols_and_cli(self):
        source = ("if __CPU_ORIGINAL__\ndb 0\nendif\n"
                  "if __CPU_J11__\ndb 1\nendif\n"
                  "if __CPU_UCODE__\ndb 2\nendif\n")
        for value, cpu in enumerate(PROFILES):
            out, _ = self.assemble(source, extra=(f"--cpu={cpu}",))
            self.assertEqual(out.read_bytes(), bytes([value]))
        self.assemble("b *\n", extra=("-D__CPU_UCODE__=1",), ok=False)
        for option in ("--cpu=bad", "--cpu=", "--unknown"):
            self.run_tool("microasm", option, ok=False)
        self.run_tool("microasm", "--cpu", ok=False)
        self.assertIn("original", self.run_tool("microasm", "--list-cpus"))
        self.assertIn("--cpu", self.run_tool("microasm", "--help"))

    def test_immediate_context_bounds(self):
        for cpu, limit in (("j11", 31), ("ucode", 63)):
            for instruction in ("gget", "gset"):
                for value in (0, limit):
                    self.assemble(f"{instruction} v0, {value}\n", cpu)
                for value in (-1, limit + 1, 256):
                    self.assemble(f"{instruction} v0, {value}\n", cpu, ok=False)
                self.assemble(f"{instruction} v0, later\nlater equ {limit}\n", cpu)
                self.assemble(f"{instruction} v0, later\nlater equ {limit + 1}\n",
                              cpu, ok=False)

    def test_ldi8_range_and_forward_constant(self):
        for value in (0, 127, 128, 255):
            out, _ = self.assemble(f"ldi8 v0, {value}\n", "ucode")
            self.assertEqual(out.read_bytes(), bytes((0x63, value)))
        for value in (-1, 256, 65536):
            self.assemble(f"ldi8 v0, {value}\n", "ucode", ok=False)
        self.assemble("ldi8 v0, later\nlater equ 255\n", "ucode")
        self.assemble("ldi8 v0, later\nlater equ 256\n", "ucode", ok=False)

    def test_ucode_pc_destinations(self):
        for instruction in ("ldi8 pc, 0", "setl pc, 0", "seth pc, 0",
                            "movl pc, v0", "ldr pc, v0, 0", "ldrl pc, v0, 0",
                            "add pc, v0, 0", "subb pc, v0, 0", "shl pc, v0, 1",
                            "shr pc, v0, 1", "sxt pc, v0", "getf pc"):
            with self.subTest(instruction=instruction):
                self.assemble(instruction + "\n", "ucode", ok=False)
        self.assemble("mov pc, v0\ngget pc, 63\nggetr pc, v0\n"
                      "gset pc, 63\ngsetr pc, v0\nstr pc, v0, 0\n"
                      "eq v0, 0\n", "ucode")

    def test_old_pc_and_const4_compatibility(self):
        for cpu in ("original", "j11"):
            self.assemble("setl pc, 0\nseth pc, 0\nmovl pc, v0\n"
                          "ldr pc, v0, 0\nadd pc, v0, 1\n", cpu)
            out, _ = self.assemble("add v0, v1, 16\nadd v0, v1, -1\n", cpu)
            self.assertEqual(out.read_bytes(), bytes.fromhex("8b818b9f"))
        for value in (-1, 16):
            self.assemble(f"add v0, v1, {value}\n", "ucode", ok=False)
        self.assemble("add v0, v1, 15\n", "ucode")

    def test_object_tags_and_matching_link(self):
        for tag, cpu in enumerate(PROFILES):
            first, _ = self.assemble("setl v0, 1\n", cpu, object_file=True)
            second, _ = self.assemble("seth v0, 2\n", cpu, object_file=True)
            self.assertEqual(struct.unpack_from("<H", first.read_bytes(), 0x10)[0], tag)
            self.assertEqual(struct.unpack_from("<H", first.read_bytes(), 2)[0], (1, 2, 4)[tag])
            output = self.directory / f"{cpu}.bin"
            self.run_tool("microlink", "-binary", "-o", output, first, second)
            self.assertEqual(output.read_bytes(), bytes.fromhex("43015302"))

    def test_link_rejects_mixed_cpus(self):
        objects = {cpu: self.assemble("b *\n", cpu, object_file=True)[0]
                   for cpu in PROFILES}
        for left in PROFILES:
            for right in set(PROFILES) - {left}:
                output = self.directory / "bad.bin"
                log = self.run_tool("microlink", "-binary", "-o", output,
                                    objects[left], objects[right], ok=False)
                self.assertIn("Cannot link CPU", log)
                self.assertFalse(output.exists())

    def test_unsupported_immediate_relocations(self):
        for cpu in ("j11", "ucode"):
            self.assemble("extern target\ngget v0, target\n", cpu,
                          object_file=True, ok=False)
        self.assemble("extern target\nldi8 v0, target\n", "ucode",
                      object_file=True, ok=False)
        self.assemble("ldi8 v0, target\ntarget\nb *\n", "ucode",
                      object_file=True, ok=False)
        self.assemble("setl v0, target\nseth v0, /target\ntarget\nb *\n",
                      "ucode", object_file=True)

    def test_disassembly_uses_cpu_not_operand_heuristics(self):
        source = "gget pc, 0\ngset pc, 0\ngget v0, 31\nggetr v0, pc\n"
        binary, _ = self.assemble(source, "j11")
        listing = self.run_tool("microdis", "--cpu=j11", "-binary", binary)
        for instruction in ("gget pc, $0", "gset pc, $0", "gget v0, $1F", "ggetr v0, pc"):
            self.assertIn(instruction, listing)
        self.assertIn("sws", self.run_tool("microdis", binary))
        obj, _ = self.assemble("ldi8 v0, 255\ngget pc, 63\n", "ucode",
                              object_file=True)
        listing = self.run_tool("microdis", obj)
        self.assertIn("ldi8 v0, $FF", listing)
        self.assertIn("gget pc, $3F", listing)
        self.run_tool("microdis", "--cpu", "j11", obj, ok=False)

    def test_disassembler_does_not_emit_unsupported_pc_writes(self):
        out, _ = self.assemble("setl pc, 0\n", "original")
        self.assertIn("dw $0040", self.run_tool("microdis", "--cpu=ucode", out))

    def test_legacy_object_reserved_field_is_not_a_cpu_tag(self):
        obj, _ = self.assemble("b *\n", "original", object_file=True)
        data = bytearray(obj.read_bytes())
        struct.pack_into("<H", data, 0x10, 123)
        obj.write_bytes(data)
        self.run_tool("microdis", obj)
        self.run_tool("microlink", "-o", self.directory / "legacy.mem", obj)

    def test_unknown_object_tag_and_short_file(self):
        obj, _ = self.assemble("b *\n", "original", object_file=True)
        data = bytearray(obj.read_bytes())
        struct.pack_into("<H", data, 2, 2)
        struct.pack_into("<H", data, 0x10, 99)
        obj.write_bytes(data)
        self.run_tool("microdis", "-object", obj, ok=False)
        self.run_tool("microlink", obj, ok=False)
        obj.write_bytes(b"")
        self.run_tool("microdis", "-object", obj, ok=False)

    def test_absolute_transfers_all_encodings(self):
        for name, prefix in (("call", 0x70), ("jmp", 0xf0)):
            source = "".join(f"{name} {word * 2}\n" for word in range(4096))
            out, _ = self.assemble(source, "ucode")
            expected = b"".join(bytes((prefix | (word >> 8), word & 255))
                                for word in range(4096))
            self.assertEqual(out.read_bytes(), expected)
            listing = self.run_tool("microdis", "--cpu=ucode", out)
            self.assertIn(f"{name} $1000", listing)
            self.assertIn(f"{name} $1FFE", listing)
            for cpu in ("original", "j11"):
                self.assemble(f"{name} 0\n", cpu, ok=False)
            for target in ("-2", "1", "8192", "later\nlater equ 3", "missing_label"):
                self.assemble(f"{name} {target}\n", "ucode", ok=False)
        out, _ = self.assemble("call end\njmp end\nend\nret\nxor v0, v1, v2\n", "ucode")
        self.assertEqual(out.read_bytes(), bytes.fromhex("7002f00280402b94"))
        self.assertIn("ret", self.run_tool("microdis", "--cpu=ucode", out))
        self.assemble("ret v0\n", "ucode", ok=False)

    def test_absolute_transfer_relocations(self):
        first, _ = self.assemble("extern target\ncall target\njmp local\nlocal\nret\n",
                                 "ucode", object_file=True)
        second, _ = self.assemble("public target\ntarget\nret\n", "ucode", object_file=True)
        out = self.directory / "linked.bin"
        self.run_tool("microlink", "-binary", "-o", out, first, second)
        self.assertEqual(out.read_bytes(), bytes.fromhex("7003f00280408040"))
        self.assertIn("reloc uaddr12", self.run_tool("microdis", first))
        self.run_tool("microlink", "-binary", "-org", "8192", "-o", out,
                      first, second, ok=False)
        self.run_tool("microlink", "-binary", "-org", "1", "-o", out,
                      first, second, ok=False)

    def test_reject_obsolete_ucode_objects(self):
        obj, _ = self.assemble("ret\n", "ucode", object_file=True)
        data = bytearray(obj.read_bytes())
        struct.pack_into("<H", data, 2, 2)
        obj.write_bytes(data)
        self.run_tool("microdis", "-object", obj, ok=False)
        self.run_tool("microlink", obj, ok=False)

    def test_carry_arithmetic_encodings_and_profiles(self):
        regs = ("pc", "sp", "lr", "v0", "v1", "v2", "v3", "v4")
        for name, opcode in (("adc", 7), ("sbc", 13)):
            source, expected = [], bytearray()
            for rd in range(1, 8):
                for ra in range(8):
                    for rb in range(24):
                        operand = str(rb) if rb < 16 else regs[rb - 16]
                        source.append(f"{name} {regs[rd]}, {regs[ra]}, {operand}\n")
                        field = (rb << 1 | 1) if rb < 16 else (rb - 16) << 2
                        expected.extend((opcode << 3 | rd, ra << 5 | field))
            out, _ = self.assemble("".join(source), "ucode")
            self.assertEqual(out.read_bytes(), expected)
            listing = self.run_tool("microdis", "--cpu=ucode", out)
            instructions = re.findall(r"^[0-9A-F]{4}: [0-9A-F]{4}    (.*)$", listing, re.M)
            again, _ = self.assemble("\n".join(instructions) + "\n", "ucode")
            self.assertEqual(again.read_bytes(), expected)
            for cpu in ("original", "j11"):
                self.assemble(f"{name} v0, v1, v2\n", cpu, ok=False)
                self.assertNotIn(f"    {name} ", self.run_tool("microdis", f"--cpu={cpu}", out))
            for operand in ("-1", "16", "missing"):
                self.assemble(f"{name} v0, v1, {operand}\n", "ucode", ok=False)
            self.assemble(f"{name} pc, v1, 0\n", "ucode", ok=False)

    def test_zero_branches_all_encodings_and_roundtrip(self):
        regs = ("pc", "sp", "lr", "v0", "v1", "v2", "v3", "v4")
        for name, mode in (("cbz", 1), ("cbnz", 2)):
            for rd, reg in enumerate(regs):
                source, expected = ["org 128\n"], bytearray()
                for i, rel in enumerate(range(-32, 32)):
                    source.append(f"{name} {reg}, {128 + i * 2 + rel * 2}\n")
                    expected.extend((0xe0 | rd, mode << 6 | (rel & 63)))
                out, _ = self.assemble("".join(source), "ucode")
                self.assertEqual(out.read_bytes(), expected)
                listing = self.run_tool("microdis", "--cpu=ucode", "-org", 128, out)
                instructions = re.findall(r"^[0-9A-F]{4}: [0-9A-F]{4}    (.*)$", listing, re.M)
                again, _ = self.assemble("org 128\n" + "\n".join(instructions) + "\n", "ucode")
                self.assertEqual(again.read_bytes(), expected)

    def test_zero_branch_bounds_profiles_and_reserved_getf(self):
        for name in ("cbz", "cbnz"):
            for cpu in ("original", "j11"):
                self.assemble(f"{name} v0, *\n", cpu, ok=False)
            for target in ("*+64", "*-66", "*+1", "8192", "-2", "missing", "/here"):
                self.assemble(f"org 128\nhere\n{name} v0, {target}\n", "ucode", ok=False)
            self.assemble(f"org 1\n{name} v0, 2\n", "ucode", ok=False)
        for source, encoding, origin, instruction in (
                ("org 8190\ncbz pc, 0\n", "e041", 8190, "cbz pc, $0000"),
                ("cbnz v4, 8190\n", "e7bf", 0, "cbnz v4, $1FFE")):
            out, _ = self.assemble(source, "ucode")
            self.assertEqual(out.read_bytes().hex(), encoding)
            self.assertIn(instruction, self.run_tool("microdis", "--cpu=ucode", "-org", origin, out))
        out, _ = self.assemble("dw $c0e3\ndw $01e3\ngetf v0\n", "ucode")
        listing = self.run_tool("microdis", "--cpu=ucode", out)
        for text in ("dw $C0E3", "dw $01E3", "getf v0"):
            self.assertIn(text, listing)

    def test_zero_branch_local_object_and_version_compatibility(self):
        source = "first\ncbz v0, next\ncbnz pc, first+2\nnext\ncbnz v4, *-2\nret\n"
        obj, _ = self.assemble(source, "ucode", object_file=True)
        binary, _ = self.assemble(source, "ucode")
        out = self.directory / "local.bin"
        for origin in (0, 128, 8184):
            self.run_tool("microlink", "-binary", "-org", origin, "-o", out, obj)
            self.assertEqual(out.read_bytes(), binary.read_bytes())
        for origin in (1, 8192):
            self.run_tool("microlink", "-binary", "-org", origin, "-o", out, obj, ok=False)
        for source in ("extern x\ncbz v0, x\n", "cbz v0, 0\n", "x equ 0\ncbz v0, x\n",
                       "x\ncbz v0, 2*x\n", "x\ncbz v0, x*2\n", "x\ncbz v0, 2-x\n",
                       "x\ncbz v0, x+*\n"):
            _, log = self.assemble(source, "ucode", object_file=True, ok=False)
            self.assertIn("local label or *", log)
        old, _ = self.assemble("ret\n", "ucode", object_file=True)
        data = bytearray(old.read_bytes())
        struct.pack_into("<H", data, 2, 3)
        old.write_bytes(data)
        self.assertIn("ret", self.run_tool("microdis", old))
        self.run_tool("microlink", "-binary", "-o", out, old, obj)
        self.assertEqual(out.read_bytes(), bytes.fromhex("8040") + binary.read_bytes())


if __name__ == "__main__":
    unittest.main()

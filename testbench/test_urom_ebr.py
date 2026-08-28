"""Check deterministic binary-to-INITVAL packing; no vendor tools required."""
import importlib.util
from pathlib import Path
import re
import struct
import unittest

spec = importlib.util.spec_from_file_location(
    "make_urom_ebr", Path(__file__).resolve().parents[1] / "ucode/make_urom_ebr.py")
packer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packer)


class UromPacking(unittest.TestCase):
    def test_all_slots_and_banks(self):
        for words in (512, 1024, 3072, 3584):
            code_words = words - 64
            image = [(i * 257 + 0x1234) & 0xffff for i in range(code_words)]
            binary = struct.pack(f"<{code_words}H", *image)
            verilog = packer.generate(binary, words)
            rows = re.findall(r'\.INITVAL_[0-9A-F]{2}\("0x([0-9A-F]{80})"\)', verilog)
            decoded = []
            for row in rows:
                decoded.extend((int(row, 16) >> (20 * i)) & 0xfffff for i in range(16))
            self.assertEqual(decoded, image + [0] * 64)  # includes unused slot bits
            self.assertEqual(verilog.count("    PDPW8KC #("), words // 512)
            mem = packer.generate_mem(binary, words).split()
            self.assertEqual(mem[0], "@0000")
            self.assertEqual([int(value, 16) for value in mem[1:]], decoded)

    def test_padding(self):
        verilog = packer.generate(b"\x34\x12", 512)
        row = re.search(r'\.INITVAL_00\("0x([0-9A-F]+)"\)', verilog)[1]
        self.assertEqual(int(row, 16) & 0xfffff, 0x1234)
        self.assertEqual((int(row, 16) >> 20) & 0xfffff, 0x00b0)
        self.assertEqual(packer.make_image(b"\x34\x12", 512)[447], 0x00b0)
        self.assertEqual(packer.make_image(b"\x34\x12", 512)[448:], [0] * 64)

    def test_writes_are_confined_to_context(self):
        for words in (512, 1024, 3072, 3584):
            verilog = packer.generate(b"", words)
            self.assertEqual(verilog.count("    ) context_ebr ("), 1)
            self.assertEqual(verilog.count(".CEW(write_enable && !rst)"), 1)
            self.assertEqual(verilog.count(".CEW(1'b0)"), words // 512 - 1)
            for bit in range(6, 9):
                self.assertEqual(verilog.count(f".ADW{bit}(1'b1)"), 1)
            for bit in range(16):
                self.assertIn(f".DI{bit}(write_data[{bit}])", verilog)

    def test_code_context_boundary(self):
        for words in (512, 1024, 3072, 3584):
            binary = bytes((words - 64) * 2)
            self.assertEqual(len(packer.make_image(binary, words)), words)
            for emit in (packer.generate, packer.generate_mem):
                with self.assertRaisesRegex(ValueError, "64 reserved for context"):
                    emit(binary + bytes(2), words)

    def test_bad_size(self):
        for words in (0, 511, 513, 4096):
            with self.assertRaises(ValueError):
                packer.generate(b"", words)
        for binary in (b"\x00", bytes(1026)):
            with self.assertRaises(ValueError):
                packer.generate(binary, 512)


if __name__ == "__main__":
    unittest.main()

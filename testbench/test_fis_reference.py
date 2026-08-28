"""Hand-calculated anchors for the independent exact FIS oracle."""
from fractions import Fraction
import unittest
from run_fis_reference import decode, encode, reference


class FISReferenceTest(unittest.TestCase):
    def test_format(self):
        self.assertEqual(decode(0x40800000), 1)
        self.assertEqual(decode(0xc0c00000), Fraction(-3, 2))
        self.assertEqual(decode(0x00800000), Fraction(2) ** -128)
        self.assertEqual(decode(0x807fffff), 0)
        self.assertEqual(decode(0x007fffff), 0)

    def test_rounding(self):
        self.assertEqual(encode(1 + Fraction(1, 1 << 24)), (0x40800001, 0, False))
        self.assertEqual(encode(-1 - Fraction(1, 1 << 24)), (0xc0800001, 8, False))
        self.assertEqual(encode(1 + Fraction(1, 1 << 25)), (0x40800000, 0, False))
        self.assertEqual(encode(1 - Fraction(1, 1 << 25)), (0x40800000, 0, False))
        self.assertEqual(encode(Fraction(2) - Fraction(1, 1 << 24)), (0x41000000, 0, False))

    def test_errors_and_zero(self):
        self.assertEqual(encode(Fraction(2) ** 127), (None, 2, True))
        self.assertEqual(encode(Fraction(2) ** -129), (None, 10, True))
        self.assertEqual(reference(3, 0x40800000, 0), (0x40800000, 11, True))
        self.assertEqual(reference(3, 0, 0), (0, 11, True))
        self.assertEqual(reference(1, 0x40800000, 0x40800000), (0, 4, False))
        self.assertEqual(reference(3, 0x40800000, 0x40c00000), (0x402aaaab, 0, False))


if __name__ == '__main__':
    unittest.main()

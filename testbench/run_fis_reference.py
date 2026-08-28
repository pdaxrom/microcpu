#!/usr/bin/env python3
"""Exact DEC F-format arithmetic oracle -> microasm11 guest tests -> RTL.

No host float is used: Fraction supplies exact rational arithmetic, followed
by one rounding to 24 significant bits (nearest, ties away from zero).
Generated assembly, binary and hex files stay under ignored build/.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from fractions import Fraction
from pathlib import Path
import random
import subprocess


def decode(bits):
    exponent = (bits >> 23) & 255
    if not exponent:
        return Fraction(0)
    mantissa = (bits & 0x7fffff) | 0x800000
    value = Fraction(mantissa) * Fraction(2) ** (exponent - 152)
    return -value if bits & 0x80000000 else value


def encode(value):
    if not value:
        return 0, 4, False
    sign = value < 0
    magnitude = abs(value)
    exponent = magnitude.numerator.bit_length() - magnitude.denominator.bit_length() + 1
    if magnitude < Fraction(2) ** (exponent - 1):
        exponent -= 1
    scaled = magnitude * Fraction(2) ** (24 - exponent)
    mantissa, remainder = divmod(scaled.numerator, scaled.denominator)
    if 2 * remainder >= scaled.denominator:
        mantissa += 1
    if mantissa == 1 << 24:
        mantissa >>= 1
        exponent += 1
    exponent += 128
    if exponent <= 0:
        return None, 10, True
    if exponent > 255:
        return None, 2, True
    return ((int(sign) << 31) | (exponent << 23) | (mantissa & 0x7fffff)), 8 * sign, False


def reference(op, a, b):
    av, bv = decode(a), decode(b)
    if op == 3 and not bv:
        return a, 11, True
    result = (av + bv if op == 0 else av - bv if op == 1 else
              av * bv if op == 2 else av / bv)
    bits, flags, error = encode(result)
    return a if error else bits, flags, error


def vectors(seed, count):
    # Deterministic cross-product stresses zeros, carry/borrow, cancellation,
    # exponent endpoints, and exact halfway cases before random samples.
    special = [0, 0x80000000, 0x007fffff, 0x807fffff,
               0x00800000, 0x00800001, 0x00ffffff, 0x01000000,
               0x34800000, 0x35000000, 0x3fffffff, 0x40000000,
               0x40800000, 0x40800001, 0x40ffffff, 0x41000000,
               0x7f000000, 0x7f7fffff, 0x7fffffff,
               0xbf800000, 0xc0800000, 0xc0800001, 0xffffffff]
    for op in range(4):
        for a in special:
            for b in special:
                yield op, a, b
    # Both sides of half-ULP, including the asymmetric spacing at powers of
    # two, rounding carry, and underflow/overflow exponent endpoints.
    for exponent in (1, 2, 128, 129, 254, 255):
        for fraction in (0, 1, 0x7fffff):
            a = (exponent << 23) | fraction
            for gap in (1, 23, 24, 25, 30, 31):
                if exponent <= gap:
                    continue
                for tail in (0, 1, 0x7fffff):
                    b = ((exponent - gap) << 23) | tail
                    for op in (0, 1):
                        yield op, a, b
                        yield op, a | 0x80000000, b | 0x80000000
    rng = random.Random(seed)
    for i in range(count):
        a = rng.getrandbits(32)
        b = rng.getrandbits(32)
        # Half of random samples force close exponents/cancellation.
        if i & 1:
            exponent = max(1, min(255, ((a >> 23) & 255) + rng.randrange(-2, 3)))
            b = (b & 0x807fffff) | (exponent << 23)
        yield i % 4, a, b


def run(args):
    root = Path(__file__).resolve().parent
    output = root / 'build' / 'fis_reference'
    output.mkdir(parents=True, exist_ok=True)
    corpus = list(vectors(args.seed, args.random))
    if args.limit:
        corpus = corpus[:args.limit]
    def batch(start):
        cases = corpus[start:start + args.batch]
        source = output / f'cases_{start:05d}.asm'
        lines = ['\tinclude ../../j11_programs/fis_test.inc', 'table']
        for op, a, b in cases:
            answer, flags, error = reference(op, a, b)
            values = [b >> 16, b & 65535, a >> 16, a & 65535,
                      answer >> 16, answer & 65535, 0o340 | flags, int(error)]
            lines.append(f'; A={a:08x} B={b:08x}')
            lines.append('\tdw do_' + ('add', 'sub', 'mul', 'div')[op] + ', ' +
                         ', '.join(f'0{value:o}' for value in values))
        lines.append('end_table')
        source.write_text('\n'.join(lines) + '\n')
        binary = source.with_suffix('.bin')
        result = subprocess.run([args.asm11, '-binary', '--cpu', 'dcj-11', str(source), str(binary)],
                                capture_output=True, text=True, cwd=root)
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
        image = source.with_suffix('.hex')
        image.write_text('@0000\n' + binary.read_bytes().hex(' ') + '\n')
        result = subprocess.run([args.vvp, args.testbench, f'+PROGRAM={image}', '+TIMEOUT=10000000'],
                                cwd=root, capture_output=True, text=True, timeout=240)
        if result.returncode:
            raise RuntimeError(f'{source}\n{result.stdout}{result.stderr}')
        return len(cases)
    completed = 0
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        pending = [pool.submit(batch, start) for start in range(0, len(corpus), args.batch)]
        try:
            for result in as_completed(pending):
                completed += result.result()
                print(f'FIS exact reference: {completed}/{len(corpus)}', flush=True)
        except BaseException:
            for result in pending:
                result.cancel()
            raise
    print(f'PASS: {len(corpus)} FIS exact-reference cases', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--asm11', default='../../../PROJECTS/k1801vm1/microasm11/microasm11')
    parser.add_argument('--vvp', default='vvp')
    parser.add_argument('--testbench', default='build/tb_j11_fis.vvp')
    parser.add_argument('--seed', type=int, default=0x11f15)
    parser.add_argument('--random', type=int, default=1024)
    parser.add_argument('--batch', type=int, default=64)
    parser.add_argument('--jobs', type=int, default=4)
    parser.add_argument('--limit', type=int, default=0)
    args = parser.parse_args()
    if args.batch < 1 or args.batch > 100 or args.jobs < 1 or args.random < 0 or args.limit < 0:
        parser.error('batch must be 1..100; jobs positive; random/limit nonnegative')
    run(args)

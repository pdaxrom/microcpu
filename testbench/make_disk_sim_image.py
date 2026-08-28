#!/usr/bin/env python3
"""Portable simulation image, including a deliberately over-budget 8-EBR case.

The production EBR packer still rejects sizes beyond HC1200's seven blocks.
This helper never generates vendor RTL or claims that 4096 words fit HC1200.
"""
import argparse
from pathlib import Path
import struct

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("binary", type=Path)
parser.add_argument("--words", type=int, choices=(3584, 4096), default=4096)
args = parser.parse_args()
code = args.binary.read_bytes()
if len(code) % 2 or len(code) // 2 > args.words - 64:
    parser.error("code overlaps the 64-word context")
image = list(struct.unpack(f"<{len(code)//2}H", code))
image += [0x00b0] * (args.words - 64 - len(image)) + [0] * 64
print("@0000")
for offset in range(0, len(image), 16):
    print(" ".join(f"{word:04x}" for word in image[offset:offset+16]))

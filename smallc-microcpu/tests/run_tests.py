#!/usr/bin/env python3
"""Run generated Small-C microcpu binaries and verify V0."""

from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys


EXPECTED = {
    "001_return_const": 123,
    "002_add": 5,
    "003_local_var": 12,
    "004_global_var": 11,
    "005_if_else": 1,
    "006_while": 10,
    "007_call": 42,
}

REG_RE = re.compile(r"\br3=([0-9a-fA-F]{4})\b")


def run_one(emulator: pathlib.Path, binary: pathlib.Path) -> bool:
    stem = binary.stem
    expected = EXPECTED.get(stem)
    if expected is None:
        print(f"{stem}: no expected value", file=sys.stderr)
        return False
    proc = subprocess.run(
        [
            str(emulator),
            "--board",
            "hc1200-cpu",
            "--format",
            "bin",
            "--stop-on-self-branch",
            "--dump-regs",
            "--quiet-uart",
            str(binary),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    output = proc.stdout + proc.stderr
    match = REG_RE.search(output)
    if proc.returncode != 0 or match is None:
        print(output, file=sys.stderr)
        return False
    actual = int(match.group(1), 16)
    if actual != (expected & 0xFFFF):
        print(f"{stem}: V0={actual} expected {expected}", file=sys.stderr)
        return False
    print(f"{stem}: V0={actual}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--emulator", required=True, type=pathlib.Path)
    parser.add_argument("binaries", nargs="+", type=pathlib.Path)
    args = parser.parse_args()

    ok = True
    for binary in args.binaries:
        ok = run_one(args.emulator, binary) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

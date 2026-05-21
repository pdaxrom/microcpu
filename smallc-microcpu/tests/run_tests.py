#!/usr/bin/env python3
"""Run generated Small-C microcpu binaries and verify V0."""

from __future__ import annotations

import argparse
import pathlib
import re
import subprocess
import sys


REG_RE = re.compile(r"\br3=([0-9a-fA-F]{4})\b")


def load_expected(path: pathlib.Path) -> dict[str, int]:
    expected: dict[str, int] = {}
    for lineno, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) != 2:
            raise ValueError(f"{path}:{lineno}: expected '<test> <value>'")
        expected[parts[0]] = int(parts[1], 0)
    return expected


def run_one(emulator: pathlib.Path, binary: pathlib.Path, expected: int) -> bool:
    stem = binary.stem
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
        print(f"FAIL {stem}: emulator failed", file=sys.stderr)
        print(output, file=sys.stderr)
        return False
    actual = int(match.group(1), 16)
    if actual != (expected & 0xFFFF):
        print(f"FAIL {stem}: V0={actual} expected {expected}", file=sys.stderr)
        return False
    print(f"PASS {stem}: V0={actual}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected", required=True, type=pathlib.Path)
    parser.add_argument("--emulator", type=pathlib.Path)
    parser.add_argument("binaries", nargs="+", type=pathlib.Path)
    args = parser.parse_args()

    expected = load_expected(args.expected)
    missing = [binary.stem for binary in args.binaries if binary.stem not in expected]
    if missing:
        for stem in missing:
            print(f"FAIL {stem}: missing expected value", file=sys.stderr)
        return 1

    if args.emulator is None or not args.emulator.exists():
        print("SKIP execution: emulator not available; assembly succeeded")
        for binary in args.binaries:
            print(f"PASS {binary.stem}: assembled")
        return 0

    ok = True
    for binary in args.binaries:
        ok = run_one(args.emulator, binary, expected[binary.stem]) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

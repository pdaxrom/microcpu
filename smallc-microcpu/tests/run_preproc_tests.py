#!/usr/bin/env python3
"""Run standalone smallcpp preprocessor tests."""

from __future__ import annotations

import argparse
import pathlib
import shlex
import subprocess
import sys


def shell_join(argv: list[str]) -> str:
    return " ".join(shlex.quote(arg) for arg in argv)


def normalize(text: str) -> str:
    lines = []
    for line in text.splitlines():
        line = line.rstrip()
        if line:
            lines.append(line)
    return "\n".join(lines) + "\n"


def run_one(source: pathlib.Path, expected: pathlib.Path, args: argparse.Namespace) -> bool:
    name = source.stem
    out = args.build_dir / f"{name}.i"
    log = args.build_dir / f"{name}.log"
    argv = [str(args.preprocessor), "-o", str(out)]
    for include_dir in args.include_dir:
        argv.extend(["-I", str(include_dir)])
    argv.append(str(source))
    proc = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
    with log.open("w") as fp:
        fp.write("$ " + shell_join(argv) + "\n")
        fp.write(f"exit={proc.returncode}\n")
        if proc.stdout:
            fp.write("-- stdout --\n")
            fp.write(proc.stdout)
        if proc.stderr:
            fp.write("-- stderr --\n")
            fp.write(proc.stderr)
    print(f"{name}:")
    if proc.returncode != 0:
        print("  PREPROCESS FAIL")
        print(f"  log: {log}")
        return False
    actual_text = out.read_text() if out.exists() else ""
    expected_text = expected.read_text()
    if normalize(actual_text) != normalize(expected_text):
        print("  PREPROCESS FAIL output mismatch")
        print(f"  output: {out}")
        print(f"  expected: {expected}")
        return False
    print("  PREPROCESS PASS")
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--preprocessor", required=True, type=pathlib.Path)
    parser.add_argument("--build-dir", default=pathlib.Path("build/tests-preproc"), type=pathlib.Path)
    parser.add_argument("--test-dir", default=pathlib.Path("tests-preproc"), type=pathlib.Path)
    parser.add_argument("--include-dir", action="append", default=[], type=pathlib.Path)
    parser.add_argument("--test")
    args = parser.parse_args()
    args.build_dir.mkdir(parents=True, exist_ok=True)
    tests = sorted(args.test_dir.glob("[0-9][0-9][0-9]_*.c"))
    if args.test:
        tests = [path for path in tests if path.stem == args.test]
        if not tests:
            print(f"FAIL: unknown preprocessor test {args.test}", file=sys.stderr)
            return 1
    ok = True
    for source in tests:
        expected = source.with_suffix(".i")
        if not expected.exists():
            print(f"FAIL: missing expected output {expected}", file=sys.stderr)
            ok = False
            continue
        ok = run_one(source, expected, args) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

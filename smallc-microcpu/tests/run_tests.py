#!/usr/bin/env python3
"""Compile, assemble, run, and verify Small-C microcpu tests."""

from __future__ import annotations

import argparse
import pathlib
import re
import shlex
import subprocess
import sys
from collections import OrderedDict


REG_RE = re.compile(r"\b(?:v0|r3)=([0-9a-fA-F]{4})\b")


def shell_join(argv: list[str]) -> str:
    return " ".join(shlex.quote(arg) for arg in argv)


def load_expected(path: pathlib.Path) -> "OrderedDict[str, int]":
    expected: "OrderedDict[str, int]" = OrderedDict()
    for lineno, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) != 2:
            raise ValueError(f"{path}:{lineno}: expected '<test> <value>'")
        expected[parts[0]] = int(parts[1], 0)
    return expected


def discover_tests(test_dir: pathlib.Path) -> dict[str, pathlib.Path]:
    return {
        path.stem: path
        for path in sorted(test_dir.glob("[0-9][0-9][0-9]_*.c"))
    }


def normalize_test_name(name: str) -> str:
    path = pathlib.Path(name)
    if path.suffix == ".c":
        return path.stem
    return path.name


def validate_manifest(
    tests: dict[str, pathlib.Path],
    expected: "OrderedDict[str, int]",
) -> bool:
    ok = True
    for name in expected:
        if name not in tests:
            print(f"FAIL manifest: expected value for {name}, but tests/{name}.c is missing", file=sys.stderr)
            ok = False
    for name in tests:
        if name not in expected:
            print(f"FAIL manifest: tests/{name}.c has no expected value", file=sys.stderr)
            ok = False
    return ok


def append_log(log_path: pathlib.Path, title: str, argv: list[str], proc: subprocess.CompletedProcess[str]) -> None:
    with log_path.open("a") as log:
        log.write(f"== {title} ==\n")
        log.write(f"$ {shell_join(argv)}\n")
        log.write(f"exit={proc.returncode}\n")
        if proc.stdout:
            log.write("-- stdout --\n")
            log.write(proc.stdout)
            if not proc.stdout.endswith("\n"):
                log.write("\n")
        if proc.stderr:
            log.write("-- stderr --\n")
            log.write(proc.stderr)
            if not proc.stderr.endswith("\n"):
                log.write("\n")
        log.write("\n")


def compile_test(compiler: pathlib.Path, source: pathlib.Path, asm_path: pathlib.Path, log_path: pathlib.Path) -> bool:
    argv = [str(compiler), str(source)]
    proc = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
    asm_path.write_text(proc.stdout)
    append_log(log_path, "compile", argv, proc)
    return proc.returncode == 0


def assemble_test(assembler: pathlib.Path, asm_path: pathlib.Path, bin_path: pathlib.Path, log_path: pathlib.Path) -> bool:
    argv = [str(assembler), "-binary", str(asm_path), str(bin_path)]
    proc = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
    append_log(log_path, "assemble", argv, proc)
    return proc.returncode == 0


def run_test(
    emulator: pathlib.Path,
    board: str,
    max_steps: int,
    trace: bool,
    bin_path: pathlib.Path,
    log_path: pathlib.Path,
) -> tuple[bool, int | None, str | None]:
    argv = [
        str(emulator),
        "--board",
        board,
        "--format",
        "bin",
        "--load-addr",
        "0",
        "--max-steps",
        str(max_steps),
        "--stop-on-self-branch",
        "--dump-regs",
        "--stats",
        "--quiet-uart",
    ]
    if trace:
        argv.append("--trace")
    argv.append(str(bin_path))

    proc = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
    append_log(log_path, "run", argv, proc)

    output = proc.stdout + proc.stderr
    if "stopped on self-branch" not in output:
        return False, None, "emulator did not reach self-branch halt before MAX_STEPS"
    matches = REG_RE.findall(output)
    if proc.returncode != 0 or not matches:
        return False, None, "emulator failed before final V0 could be parsed"
    return True, int(matches[-1], 16), None


def run_one(
    name: str,
    source: pathlib.Path,
    expected: int,
    args: argparse.Namespace,
) -> bool:
    asm_path = args.build_dir / f"{name}.asm"
    bin_path = args.build_dir / f"{name}.bin"
    log_path = args.build_dir / f"{name}.log"
    args.build_dir.mkdir(parents=True, exist_ok=True)
    log_path.write_text("")

    print(f"{name}:")
    if compile_test(args.compiler, source, asm_path, log_path):
        print("  COMPILE PASS")
    else:
        print("  COMPILE FAIL")
        print(f"  log: {log_path}")
        return False

    if assemble_test(args.assembler, asm_path, bin_path, log_path):
        print("  ASSEMBLE PASS")
    else:
        print("  ASSEMBLE FAIL")
        print(f"  log: {log_path}")
        return False

    run_ok, actual, reason = run_test(
        args.emulator,
        args.board,
        args.max_steps,
        args.trace,
        bin_path,
        log_path,
    )
    if not run_ok:
        print(f"  RUN FAIL {reason}")
        print(f"  log: {log_path}")
        return False

    if actual != (expected & 0xFFFF):
        print(f"  RUN FAIL expected={expected} actual={actual}")
        print(f"  log: {log_path}")
        return False

    print(f"  RUN PASS expected={expected} actual={actual}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected", required=True, type=pathlib.Path)
    parser.add_argument("--compiler", required=True, type=pathlib.Path)
    parser.add_argument("--assembler", required=True, type=pathlib.Path)
    parser.add_argument("--emulator", required=True, type=pathlib.Path)
    parser.add_argument("--board", default="hc1200-mcu")
    parser.add_argument("--max-steps", default=1_000_000, type=int)
    parser.add_argument("--build-dir", default=pathlib.Path("build/tests"), type=pathlib.Path)
    parser.add_argument("--test")
    parser.add_argument("--trace", action="store_true")
    args = parser.parse_args()

    expected = load_expected(args.expected)
    tests = discover_tests(args.expected.parent)
    if not validate_manifest(tests, expected):
        return 1

    if not args.compiler.exists():
        print(f"FAIL: compiler not found: {args.compiler}", file=sys.stderr)
        return 1
    if not args.assembler.exists():
        print(f"FAIL: assembler not found: {args.assembler}", file=sys.stderr)
        return 1
    if not args.emulator.exists():
        print(f"FAIL: emulator not found: {args.emulator}", file=sys.stderr)
        return 1

    selected = list(expected.keys())
    if args.test:
        name = normalize_test_name(args.test)
        if name not in expected:
            print(f"FAIL: unknown test {args.test}", file=sys.stderr)
            return 1
        selected = [name]

    ok = True
    for name in selected:
        ok = run_one(name, tests[name], expected[name], args) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

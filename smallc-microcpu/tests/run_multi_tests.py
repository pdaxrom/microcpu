#!/usr/bin/env python3
"""Compile, link, run, and verify multi-file Small-C microcpu tests."""

from __future__ import annotations

import argparse
import pathlib
import sys

from run_tests import (
    assemble_test,
    build_runtime_objects,
    compile_test,
    link_test,
    load_expected,
    run_test,
)


def discover_tests(test_dir: pathlib.Path) -> dict[str, pathlib.Path]:
    return {
        path.name: path
        for path in sorted(test_dir.iterdir())
        if path.is_dir() and path.name[:3].isdigit()
    }


def run_one(name: str, test_path: pathlib.Path, expected: int, args: argparse.Namespace) -> bool:
    test_build = args.build_dir
    test_build.mkdir(parents=True, exist_ok=True)
    log_path = test_build / f"{name}.log"
    bin_path = test_build / f"{name}.bin"
    log_path.write_text("")

    objects: list[pathlib.Path] = []
    print(f"{name}:")
    for source in sorted(test_path.glob("*.c")):
        stem = source.stem
        asm_path = test_build / f"{name}__{stem}.asm"
        obj_path = test_build / f"{name}__{stem}.o"
        if compile_test(args.compiler, args.include_dir, source, asm_path, log_path, True):
            print(f"  COMPILE {source.name} PASS")
        else:
            print(f"  COMPILE {source.name} FAIL")
            print(f"  log: {log_path}")
            return False
        if assemble_test(args.assembler, asm_path, obj_path, log_path, True):
            print(f"  ASSEMBLE {source.name} PASS")
        else:
            print(f"  ASSEMBLE {source.name} FAIL")
            print(f"  log: {log_path}")
            return False
        objects.append(obj_path)

    link_objects = [args.runtime_objects[0]]
    link_objects.extend(objects)
    link_objects.extend(args.runtime_objects[1:])
    if link_test(args.linker, link_objects, bin_path, log_path):
        print("  LINK PASS")
    else:
        print("  LINK FAIL")
        print(f"  log: {log_path}")
        return False

    run_ok, actual, reason, _uart_output = run_test(
        args.emulator,
        args.board,
        args.max_steps,
        args.trace,
        bin_path,
        log_path,
        None,
        False,
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
    parser.add_argument("--linker", required=True, type=pathlib.Path)
    parser.add_argument("--emulator", required=True, type=pathlib.Path)
    parser.add_argument("--board", default="hc1200-mcu")
    parser.add_argument("--max-steps", default=1_000_000, type=int)
    parser.add_argument("--build-dir", default=pathlib.Path("build/tests-multi"), type=pathlib.Path)
    parser.add_argument("--include-dir", action="append", default=[], type=pathlib.Path)
    parser.add_argument("--runtime-dir", default=pathlib.Path("runtime"), type=pathlib.Path)
    parser.add_argument("--test")
    parser.add_argument("--trace", action="store_true")
    args = parser.parse_args()

    expected = load_expected(args.expected)
    tests = discover_tests(args.expected.parent)
    ok = True
    for name in expected:
        if name not in tests:
            print(f"FAIL manifest: expected value for {name}, but test directory is missing", file=sys.stderr)
            ok = False
    for name in tests:
        if name not in expected:
            print(f"FAIL manifest: {name} has no expected value", file=sys.stderr)
            ok = False
    if not ok:
        return 1

    runtime_ok, runtime_objects = build_runtime_objects(args)
    if not runtime_ok:
        return 1
    args.runtime_objects = runtime_objects

    selected = list(expected.keys())
    if args.test:
        if args.test not in expected:
            print(f"FAIL: unknown test {args.test}", file=sys.stderr)
            return 1
        selected = [args.test]

    for name in selected:
        ok = run_one(name, tests[name], expected[name], args) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

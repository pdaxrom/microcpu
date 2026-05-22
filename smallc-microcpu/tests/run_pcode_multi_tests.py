#!/usr/bin/env python3
"""Run multi-module p-code programs through the microcpu interpreter."""

from __future__ import annotations

import argparse
import pathlib
import sys

import pcode_merge
import run_pcode_microemu as pcode


def discover_tests(test_dir: pathlib.Path) -> dict[str, pathlib.Path]:
    return {
        path.name: path
        for path in sorted(test_dir.iterdir())
        if path.is_dir() and path.name[:3].isdigit()
    }


def compile_pcode_source(
    test_name: str,
    source: pathlib.Path,
    args: argparse.Namespace,
    log_path: pathlib.Path,
) -> tuple[bool, pathlib.Path]:
    stem = source.stem
    name = f"{test_name}__{stem}"
    ok, _i_path, pca_path = pcode.compile_pcode(name, source, args, log_path)
    return ok, pca_path


def run_one(
    name: str,
    test_path: pathlib.Path,
    expected: int,
    args: argparse.Namespace,
    interp_obj: pathlib.Path,
    runtime_obj: pathlib.Path,
    rows: list[str],
) -> bool:
    log_path = args.build_dir / f"{name}.log"
    merged_pca = args.build_dir / f"{name}.merged.pca"
    pcode_asm = args.build_dir / f"{name}.pcode.asm"
    pcode_obj = args.build_dir / f"{name}.pcode.o"
    bin_path = args.build_dir / f"{name}.bin"
    log_path.write_text("")

    print(f"{name}:")
    pca_paths: list[pathlib.Path] = []
    for source in sorted(test_path.glob("*.c")):
        ok, pca_path = compile_pcode_source(name, source, args, log_path)
        if ok:
            print(f"  PCODE {source.name} PASS")
            pca_paths.append(pca_path)
        else:
            print(f"  PCODE {source.name} FAIL")
            print(f"  log: {log_path}")
            return False

    try:
        pcode_merge.merge_pca_files(pca_paths, merged_pca)
        entry, bytecode, data, data_labels, natives, externs = pcode.encode_pca(merged_pca)
        pcode.write_pcode_object_asm(pcode_asm, entry, bytecode, data, data_labels, natives, externs)
    except Exception as exc:
        print(f"  PCODE MERGE FAIL {exc}")
        print(f"  log: {log_path}")
        with log_path.open("a") as log:
            log.write(f"pcode merge error: {exc}\n")
        return False

    if pcode.assemble(args, pcode_asm, pcode_obj, log_path):
        print("  PCODE ASSEMBLE PASS")
    else:
        print("  PCODE ASSEMBLE FAIL")
        print(f"  log: {log_path}")
        return False

    link_objects = [interp_obj]
    if natives:
        link_objects.append(runtime_obj)
    link_objects.append(pcode_obj)
    if pcode.link(args, link_objects, bin_path, log_path):
        print("  LINK PASS")
    else:
        print("  LINK FAIL")
        print(f"  log: {log_path}")
        return False

    run_ok, actual, reason, _uart = pcode.run_microemu(args, bin_path, log_path, False)
    if not run_ok:
        print(f"  RUN FAIL {reason}")
        print(f"  log: {log_path}")
        return False
    if actual != (expected & 0xFFFF):
        print(f"  RUN FAIL expected={expected} actual={actual}")
        print(f"  log: {log_path}")
        return False
    print(f"  RUN PASS expected={expected} actual={actual}")

    rows.append(f"{name}:")
    rows.append(f"  p-code modules: {len(pca_paths)}")
    rows.append(f"  p-code bytecode bytes: {pcode.bytecode_size(bytecode)}")
    rows.append(f"  p-code global data bytes: {len(data)}")
    rows.append(f"  p-code native table bytes: {len(natives) * 2}")
    rows.append(f"  pcode.o size: {pcode_obj.stat().st_size}")
    rows.append(f"  linked binary bytes: {bin_path.stat().st_size}")
    return True


def normalize_test_name(name: str) -> str:
    path = pathlib.Path(name)
    return path.stem if path.suffix == ".c" else path.name


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected", required=True, type=pathlib.Path)
    parser.add_argument("--preprocessor", required=True, type=pathlib.Path)
    parser.add_argument("--cc-only", required=True, type=pathlib.Path)
    parser.add_argument("--assembler", required=True, type=pathlib.Path)
    parser.add_argument("--linker", required=True, type=pathlib.Path)
    parser.add_argument("--emulator", required=True, type=pathlib.Path)
    parser.add_argument("--runtime-dir", required=True, type=pathlib.Path)
    parser.add_argument("--build-dir", default=pathlib.Path("build/pcode-multi"), type=pathlib.Path)
    parser.add_argument("--include-dir", action="append", default=[], type=pathlib.Path)
    parser.add_argument("--board", default="hc1200-mcu")
    parser.add_argument("--max-steps", default=1_000_000, type=int)
    parser.add_argument("--test")
    args = parser.parse_args()

    expected = pcode.load_expected(args.expected)
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

    selected = list(expected.keys())
    if args.test:
        name = normalize_test_name(args.test)
        if name not in expected:
            print(f"FAIL: unknown test {args.test}", file=sys.stderr)
            return 1
        selected = [name]

    args.build_dir.mkdir(parents=True, exist_ok=True)
    interp_obj = args.build_dir / "pcode_interpreter.o"
    interp_log = args.build_dir / "pcode_interpreter.log"
    interp_log.write_text("")
    if not pcode.assemble(args, args.runtime_dir / "pcode_interpreter.asm", interp_obj, interp_log):
        print(f"FAIL: p-code interpreter assembly failed: {interp_log}", file=sys.stderr)
        return 1
    runtime_obj = args.build_dir / "runtime_object.o"
    runtime_log = args.build_dir / "runtime_object.log"
    runtime_log.write_text("")
    if not pcode.assemble(args, args.runtime_dir / "runtime_object.asm", runtime_obj, runtime_log):
        print(f"FAIL: p-code native runtime assembly failed: {runtime_log}", file=sys.stderr)
        return 1

    rows = ["P-code multi-module size report", ""]
    for name in selected:
        ok = run_one(name, tests[name], expected[name], args, interp_obj, runtime_obj, rows) and ok
    (args.build_dir / "size-report.txt").write_text("\n".join(rows) + "\n")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

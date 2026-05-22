#!/usr/bin/env python3
"""Run experimental Small-C p-code backend tests on the host interpreter."""

from __future__ import annotations

import argparse
import pathlib
import re
import shlex
import subprocess
import sys
from collections import OrderedDict

import pcode_opt


RET_RE = re.compile(r"^RET=([0-9]+)$", re.MULTILINE)
METRIC_RE = re.compile(r"^([A-Z_]+)=([0-9]+)$", re.MULTILINE)
UART_RE = re.compile(r"^UART=(.*)$", re.MULTILINE)


def shell_join(argv: list[str]) -> str:
    return " ".join(shlex.quote(arg) for arg in argv)


def decode_escapes(value: str, path: pathlib.Path, lineno: int) -> str:
    out: list[str] = []
    i = 0
    while i < len(value):
        ch = value[i]
        if ch != "\\":
            out.append(ch)
            i += 1
            continue
        i += 1
        if i >= len(value):
            raise ValueError(f"{path}:{lineno}: incomplete escape")
        esc = value[i]
        i += 1
        if esc == "n":
            out.append("\n")
        elif esc == "r":
            out.append("\r")
        elif esc == "t":
            out.append("\t")
        elif esc == "0":
            out.append("\0")
        elif esc == "\\":
            out.append("\\")
        elif esc == '"':
            out.append('"')
        elif esc == "x":
            if i + 2 > len(value):
                raise ValueError(f"{path}:{lineno}: incomplete hex escape")
            digits = value[i:i + 2]
            if not re.fullmatch(r"[0-9a-fA-F]{2}", digits):
                raise ValueError(f"{path}:{lineno}: invalid hex escape '\\x{digits}'")
            out.append(chr(int(digits, 16)))
            i += 2
        else:
            raise ValueError(f"{path}:{lineno}: unsupported escape '\\{esc}'")
    return "".join(out)


def escape_display(value: str) -> str:
    out: list[str] = []
    for ch in value:
        code = ord(ch)
        if ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\0":
            out.append("\\0")
        elif ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif code < 32 or code >= 127:
            out.append(f"\\x{code:02x}")
        else:
            out.append(ch)
    return "".join(out)


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


def load_text_manifest(path: pathlib.Path | None) -> "OrderedDict[str, str]":
    values: "OrderedDict[str, str]" = OrderedDict()
    if path is None or not path.exists():
        return values
    for lineno, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split(None, 1)
        name = parts[0]
        value = parts[1] if len(parts) == 2 else ""
        values[name] = decode_escapes(value, path, lineno)
    return values


def discover_tests(test_dir: pathlib.Path) -> dict[str, pathlib.Path]:
    return {
        path.stem: path
        for path in sorted(test_dir.glob("[0-9][0-9][0-9]_*.c"))
    }


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


def run_cmd(log_path: pathlib.Path, title: str, argv: list[str]) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
    append_log(log_path, title, argv, proc)
    return proc


def validate_manifests(
    tests: dict[str, pathlib.Path],
    expected: "OrderedDict[str, int]",
    expected_uart: "OrderedDict[str, str]",
) -> bool:
    ok = True
    for name in expected:
        if name not in tests:
            print(f"FAIL manifest: expected value for {name}, but pcode-tests/{name}.c is missing", file=sys.stderr)
            ok = False
    for name in tests:
        if name not in expected:
            print(f"FAIL manifest: pcode-tests/{name}.c has no expected value", file=sys.stderr)
            ok = False
    for name in expected_uart:
        if name not in tests:
            print(f"FAIL manifest: expected UART for {name}, but pcode-tests/{name}.c is missing", file=sys.stderr)
            ok = False
    return ok


def parse_metrics(stdout: str) -> dict[str, int]:
    metrics: dict[str, int] = {}
    for match in METRIC_RE.finditer(stdout):
        metrics[match.group(1)] = int(match.group(2))
    return metrics


def compile_pcode(
    name: str,
    source: pathlib.Path,
    args: argparse.Namespace,
    log_path: pathlib.Path,
) -> tuple[bool, pathlib.Path, pathlib.Path]:
    i_path = args.build_dir / f"{name}.i"
    pca_path = args.build_dir / f"{name}.pca"
    argv = [str(args.preprocessor), "-o", str(i_path)]
    for include_dir in args.include_dir:
        argv.extend(["-I", str(include_dir)])
    argv.append(str(source))
    proc = run_cmd(log_path, "preprocess", argv)
    if proc.returncode != 0:
        return False, i_path, pca_path
    argv = [str(args.cc_only), "--backend", "pcode", "-o", str(pca_path), str(i_path)]
    proc = run_cmd(log_path, "compile-pcode", argv)
    if proc.returncode == 0 and args.pcode_opt:
        raw_path = args.build_dir / f"{name}.raw.pca"
        pca_path.replace(raw_path)
        stats = pcode_opt.optimize_pca_file(raw_path, pca_path)
        with log_path.open("a") as log:
            log.write("== pcode-opt ==\n")
            log.write(f"removed_temp_roundtrips={stats['removed_temp_roundtrips']}\n")
            log.write(f"bytecode_before={stats['bytecode_before']}\n")
            log.write(f"bytecode_after={stats['bytecode_after']}\n")
            log.write(f"bytecode_saved={stats['bytecode_saved']}\n\n")
    return proc.returncode == 0, i_path, pca_path


def compile_native_size(
    name: str,
    i_path: pathlib.Path,
    args: argparse.Namespace,
    log_path: pathlib.Path,
) -> tuple[int | None, int | None, int | None]:
    asm_path = args.build_dir / f"{name}.native.asm"
    bin_path = args.build_dir / f"{name}.native.bin"
    argv = [str(args.cc_only), "--backend", "microcpu", "-o", str(asm_path), str(i_path)]
    proc = run_cmd(log_path, "compile-native-size", argv)
    if proc.returncode != 0:
        return None, None, None
    asm_bytes = asm_path.stat().st_size
    asm_lines = len(asm_path.read_text(errors="replace").splitlines())
    if args.assembler and args.assembler.exists():
        argv = [str(args.assembler), "-binary", str(asm_path), str(bin_path)]
        proc = run_cmd(log_path, "assemble-native-size", argv)
        if proc.returncode == 0:
            return asm_bytes, asm_lines, bin_path.stat().st_size
    return asm_bytes, asm_lines, None


def run_one(
    name: str,
    source: pathlib.Path,
    expected: int,
    args: argparse.Namespace,
    expected_uart: str | None,
    size_rows: list[str],
) -> bool:
    log_path = args.build_dir / f"{name}.log"
    args.build_dir.mkdir(parents=True, exist_ok=True)
    log_path.write_text("")

    print(f"{name}:")
    ok, i_path, pca_path = compile_pcode(name, source, args, log_path)
    if ok:
        print("  PCODE COMPILE PASS")
    else:
        print("  PCODE COMPILE FAIL")
        print(f"  log: {log_path}")
        return False

    argv = [str(args.pcinterp), "--max-steps", str(args.max_steps), str(pca_path)]
    proc = run_cmd(log_path, "pcinterp", argv)
    if proc.returncode != 0:
        print("  HOST RUN FAIL")
        print(f"  log: {log_path}")
        return False

    ret_match = RET_RE.search(proc.stdout)
    if not ret_match:
        print("  HOST RUN FAIL missing RET")
        print(f"  log: {log_path}")
        return False
    actual = int(ret_match.group(1))
    if actual != (expected & 0xFFFF):
        print(f"  HOST RUN FAIL expected={expected} actual={actual}")
        print(f"  log: {log_path}")
        return False
    print(f"  HOST RUN PASS expected={expected} actual={actual}")

    uart_match = UART_RE.search(proc.stdout)
    actual_uart = decode_escapes(uart_match.group(1), log_path, 0) if uart_match else ""
    if expected_uart is not None:
        if actual_uart != expected_uart:
            print(
                "  UART FAIL "
                f"expected={escape_display(expected_uart)} "
                f"actual={escape_display(actual_uart)}"
            )
            print(f"  log: {log_path}")
            return False
        print(
            "  UART PASS "
            f"expected={escape_display(expected_uart)} "
            f"actual={escape_display(actual_uart)}"
        )

    metrics = parse_metrics(proc.stdout)
    native_asm_bytes, native_asm_lines, native_bin_bytes = compile_native_size(name, i_path, args, log_path)
    size_rows.append(f"{name}:")
    size_rows.append(f"  raw bytecode bytes: {metrics.get('BYTECODE_BYTES', 0)}")
    size_rows.append(f"  global data bytes: {metrics.get('GLOBAL_DATA_BYTES', 0)}")
    size_rows.append(f"  native table bytes: {metrics.get('NATIVE_TABLE_BYTES', 0)}")
    size_rows.append(f"  total pcode.o data size: {metrics.get('PCODE_OBJECT_BYTES', 0)}")
    size_rows.append("  linked interpreter size: host-only in this phase")
    if native_asm_bytes is not None:
        size_rows.append(f"  native asm bytes: {native_asm_bytes}")
        size_rows.append(f"  native asm lines: {native_asm_lines}")
    if native_bin_bytes is not None:
        size_rows.append(f"  native backend binary bytes: {native_bin_bytes}")
    else:
        size_rows.append("  native backend binary bytes: unavailable")
    return True


def normalize_test_name(name: str) -> str:
    path = pathlib.Path(name)
    if path.suffix == ".c":
        return path.stem
    return path.name


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected", required=True, type=pathlib.Path)
    parser.add_argument("--expected-uart", type=pathlib.Path)
    parser.add_argument("--preprocessor", required=True, type=pathlib.Path)
    parser.add_argument("--cc-only", required=True, type=pathlib.Path)
    parser.add_argument("--pcinterp", required=True, type=pathlib.Path)
    parser.add_argument("--assembler", type=pathlib.Path)
    parser.add_argument("--build-dir", default=pathlib.Path("build/pcode"), type=pathlib.Path)
    parser.add_argument("--include-dir", action="append", default=[], type=pathlib.Path)
    parser.add_argument("--max-steps", default=1_000_000, type=int)
    parser.add_argument("--pcode-opt", action="store_true")
    parser.add_argument("--test")
    args = parser.parse_args()

    expected = load_expected(args.expected)
    expected_uart = load_text_manifest(args.expected_uart)
    tests = discover_tests(args.expected.parent)
    if not validate_manifests(tests, expected, expected_uart):
        return 1

    selected = list(expected.keys())
    if args.test:
        name = normalize_test_name(args.test)
        if name not in expected:
            print(f"FAIL: unknown test {args.test}", file=sys.stderr)
            return 1
        selected = [name]

    size_rows: list[str] = [
        "Experimental p-code size report",
        "",
    ]
    ok = True
    for name in selected:
        ok = run_one(
            name,
            tests[name],
            expected[name],
            args,
            expected_uart.get(name),
            size_rows,
        ) and ok
    args.build_dir.mkdir(parents=True, exist_ok=True)
    (args.build_dir / "size-report.txt").write_text("\n".join(size_rows) + "\n")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

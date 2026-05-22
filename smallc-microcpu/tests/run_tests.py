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


def load_text_manifest(path: pathlib.Path) -> "OrderedDict[str, str]":
    values: "OrderedDict[str, str]" = OrderedDict()
    if not path.exists():
        return values
    for lineno, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split(None, 1)
        if not parts:
            continue
        name = parts[0]
        value = parts[1] if len(parts) == 2 else ""
        values[name] = decode_escapes(value, path, lineno)
    return values


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


def validate_text_manifest(
    tests: dict[str, pathlib.Path],
    values: "OrderedDict[str, str]",
    label: str,
) -> bool:
    ok = True
    for name in values:
        if name not in tests:
            print(f"FAIL manifest: {label} entry for {name}, but tests/{name}.c is missing", file=sys.stderr)
            ok = False
    return ok


def output_text(value: str | bytes) -> str:
    if isinstance(value, bytes):
        return value.decode("latin-1")
    return value


def append_log(log_path: pathlib.Path, title: str, argv: list[str], proc: subprocess.CompletedProcess[str]) -> None:
    with log_path.open("a") as log:
        log.write(f"== {title} ==\n")
        log.write(f"$ {shell_join(argv)}\n")
        log.write(f"exit={proc.returncode}\n")
        if proc.stdout:
            stdout = output_text(proc.stdout)
            log.write("-- stdout --\n")
            log.write(stdout)
            if not stdout.endswith("\n"):
                log.write("\n")
        if proc.stderr:
            stderr = output_text(proc.stderr)
            log.write("-- stderr --\n")
            log.write(stderr)
            if not stderr.endswith("\n"):
                log.write("\n")
        log.write("\n")


def compile_test(
    compiler: pathlib.Path,
    include_dirs: list[pathlib.Path],
    source: pathlib.Path,
    asm_path: pathlib.Path,
    log_path: pathlib.Path,
) -> bool:
    argv = [str(compiler)]
    for include_dir in include_dirs:
        argv.extend(["-I", str(include_dir)])
    argv.append(str(source))
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
    uart_input: str | None,
    expect_uart: bool,
) -> tuple[bool, int | None, str | None, str]:
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
    ]
    if not expect_uart:
        argv.append("--quiet-uart")
    if uart_input is not None:
        argv.extend(["--uart-rx", escape_display(uart_input)])
    if trace:
        argv.append("--trace")
    argv.append(str(bin_path))

    proc = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    append_log(log_path, "run", argv, proc)

    uart_output = output_text(proc.stdout)
    output = uart_output + output_text(proc.stderr)
    if "stopped on self-branch" not in output:
        return False, None, "emulator did not reach self-branch halt before MAX_STEPS", uart_output
    matches = REG_RE.findall(output)
    if proc.returncode != 0 or not matches:
        return False, None, "emulator failed before final V0 could be parsed", uart_output
    return True, int(matches[-1], 16), None, uart_output


def run_one(
    name: str,
    source: pathlib.Path,
    expected: int,
    args: argparse.Namespace,
    expected_uart: str | None,
    uart_input: str | None,
) -> bool:
    asm_path = args.build_dir / f"{name}.asm"
    bin_path = args.build_dir / f"{name}.bin"
    log_path = args.build_dir / f"{name}.log"
    args.build_dir.mkdir(parents=True, exist_ok=True)
    log_path.write_text("")

    print(f"{name}:")
    if compile_test(args.compiler, args.include_dir, source, asm_path, log_path):
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

    run_ok, actual, reason, uart_output = run_test(
        args.emulator,
        args.board,
        args.max_steps,
        args.trace,
        bin_path,
        log_path,
        uart_input,
        expected_uart is not None,
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
    if expected_uart is not None:
        if reason is not None:
            print(f"  UART FAIL {reason}")
            print(f"  log: {log_path}")
            return False
        if uart_output != expected_uart:
            print(
                "  UART FAIL "
                f"expected={escape_display(expected_uart)} "
                f"actual={escape_display(uart_output)}"
            )
            print(f"  log: {log_path}")
            return False
        print(
            "  UART PASS "
            f"expected={escape_display(expected_uart)} "
            f"actual={escape_display(uart_output)}"
        )
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected", required=True, type=pathlib.Path)
    parser.add_argument("--expected-uart", type=pathlib.Path)
    parser.add_argument("--input-uart", type=pathlib.Path)
    parser.add_argument("--compiler", required=True, type=pathlib.Path)
    parser.add_argument("--assembler", required=True, type=pathlib.Path)
    parser.add_argument("--emulator", required=True, type=pathlib.Path)
    parser.add_argument("--board", default="hc1200-mcu")
    parser.add_argument("--max-steps", default=1_000_000, type=int)
    parser.add_argument("--build-dir", default=pathlib.Path("build/tests"), type=pathlib.Path)
    parser.add_argument("--include-dir", action="append", default=[], type=pathlib.Path)
    parser.add_argument("--test")
    parser.add_argument("--trace", action="store_true")
    args = parser.parse_args()

    expected = load_expected(args.expected)
    expected_uart = load_text_manifest(args.expected_uart) if args.expected_uart else OrderedDict()
    input_uart = load_text_manifest(args.input_uart) if args.input_uart else OrderedDict()
    tests = discover_tests(args.expected.parent)
    if not validate_manifest(tests, expected):
        return 1
    if not validate_text_manifest(tests, expected_uart, "expected UART"):
        return 1
    if not validate_text_manifest(tests, input_uart, "input UART"):
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
        ok = run_one(
            name,
            tests[name],
            expected[name],
            args,
            expected_uart.get(name),
            input_uart.get(name),
        ) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

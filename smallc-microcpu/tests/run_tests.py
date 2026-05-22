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
    preprocessor: pathlib.Path | None,
    cc_only: pathlib.Path | None,
    include_dirs: list[pathlib.Path],
    source: pathlib.Path,
    asm_path: pathlib.Path,
    log_path: pathlib.Path,
    object_mode: bool,
    preprocess_mode: bool,
) -> bool:
    if preprocess_mode:
        if preprocessor is None or cc_only is None:
            append_log(
                log_path,
                "compile",
                ["missing-preprocessor-or-cc-only"],
                subprocess.CompletedProcess([], 1, "", "missing split compiler tools"),
            )
            return False
        i_path = asm_path.with_suffix(".i")
        argv1 = [str(preprocessor), "-o", str(i_path)]
        for include_dir in include_dirs:
            argv1.extend(["-I", str(include_dir)])
        argv1.append(str(source))
        proc1 = subprocess.run(argv1, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
        append_log(log_path, "preprocess", argv1, proc1)
        if proc1.returncode != 0:
            return False
        argv2 = [str(cc_only)]
        if object_mode:
            argv2.append("--object")
        argv2.extend(["-o", str(asm_path), str(i_path)])
        proc2 = subprocess.run(argv2, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
        append_log(log_path, "compile", argv2, proc2)
        return proc2.returncode == 0

    argv = [str(compiler)]
    if object_mode:
        argv.append("--object")
    for include_dir in include_dirs:
        argv.extend(["-I", str(include_dir)])
    argv.append(str(source))
    proc = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
    asm_path.write_text(proc.stdout)
    append_log(log_path, "compile", argv, proc)
    return proc.returncode == 0


def assemble_test(
    assembler: pathlib.Path,
    asm_path: pathlib.Path,
    out_path: pathlib.Path,
    log_path: pathlib.Path,
    object_mode: bool,
) -> bool:
    mode = "-object" if object_mode else "-binary"
    argv = [str(assembler), mode, str(asm_path), str(out_path)]
    proc = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
    append_log(log_path, "assemble", argv, proc)
    return proc.returncode == 0


def link_test(
    linker: pathlib.Path,
    objects: list[pathlib.Path],
    bin_path: pathlib.Path,
    log_path: pathlib.Path,
) -> bool:
    argv = [str(linker), "-binary", "-o", str(bin_path)]
    argv.extend(str(path) for path in objects)
    proc = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
    append_log(log_path, "link", argv, proc)
    return proc.returncode == 0


def build_runtime_objects(args: argparse.Namespace) -> tuple[bool, list[pathlib.Path]]:
    runtime_build = args.build_dir / "__runtime"
    runtime_build.mkdir(parents=True, exist_ok=True)
    sources = [
        args.runtime_dir / "crt0_object.asm",
        args.runtime_dir / "runtime_object.asm",
        args.runtime_dir / "stack_object.asm",
    ]
    objects: list[pathlib.Path] = []
    ok = True
    for source in sources:
        obj_path = runtime_build / f"{source.stem}.o"
        log_path = runtime_build / f"{source.stem}.log"
        log_path.write_text("")
        if assemble_test(args.assembler, source, obj_path, log_path, True):
            objects.append(obj_path)
        else:
            print(f"FAIL: runtime object assembly failed: {source}", file=sys.stderr)
            print(f"  log: {log_path}", file=sys.stderr)
            ok = False
    return ok, objects


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
    obj_path = args.build_dir / f"{name}.o"
    bin_path = args.build_dir / f"{name}.bin"
    log_path = args.build_dir / f"{name}.log"
    args.build_dir.mkdir(parents=True, exist_ok=True)
    log_path.write_text("")

    print(f"{name}:")
    if compile_test(
        args.compiler,
        args.preprocessor,
        args.cc_only,
        args.include_dir,
        source,
        asm_path,
        log_path,
        args.object_mode,
        args.preprocess_mode,
    ):
        print("  COMPILE PASS")
    else:
        print("  COMPILE FAIL")
        print(f"  log: {log_path}")
        return False

    asm_out = obj_path if args.object_mode else bin_path
    if assemble_test(args.assembler, asm_path, asm_out, log_path, args.object_mode):
        print("  ASSEMBLE PASS")
    else:
        print("  ASSEMBLE FAIL")
        print(f"  log: {log_path}")
        return False

    if args.object_mode:
        link_objects = [args.runtime_objects[0], obj_path]
        link_objects.extend(args.runtime_objects[1:])
        if link_test(args.linker, link_objects, bin_path, log_path):
            print("  LINK PASS")
        else:
            print("  LINK FAIL")
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
    parser.add_argument("--preprocessor", type=pathlib.Path)
    parser.add_argument("--cc-only", type=pathlib.Path)
    parser.add_argument("--assembler", required=True, type=pathlib.Path)
    parser.add_argument("--emulator", required=True, type=pathlib.Path)
    parser.add_argument("--linker", type=pathlib.Path)
    parser.add_argument("--runtime-dir", default=pathlib.Path("runtime"), type=pathlib.Path)
    parser.add_argument("--object-mode", action="store_true")
    parser.add_argument("--preprocess-mode", action="store_true")
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
    if args.preprocess_mode:
        if args.preprocessor is None or not args.preprocessor.exists():
            print(f"FAIL: preprocessor not found: {args.preprocessor}", file=sys.stderr)
            return 1
        if args.cc_only is None or not args.cc_only.exists():
            print(f"FAIL: compiler-only tool not found: {args.cc_only}", file=sys.stderr)
            return 1
    if not args.assembler.exists():
        print(f"FAIL: assembler not found: {args.assembler}", file=sys.stderr)
        return 1
    if not args.emulator.exists():
        print(f"FAIL: emulator not found: {args.emulator}", file=sys.stderr)
        return 1
    if args.object_mode:
        if args.linker is None:
            print("FAIL: --object-mode requires --linker", file=sys.stderr)
            return 1
        if not args.linker.exists():
            print(f"FAIL: linker not found: {args.linker}", file=sys.stderr)
            return 1
        runtime_ok, runtime_objects = build_runtime_objects(args)
        if not runtime_ok:
            return 1
        args.runtime_objects = runtime_objects
    else:
        args.runtime_objects = []

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

#!/usr/bin/env python3
"""Compile selected compiler sources with smallc-microcpu and report blockers."""

from __future__ import annotations

import argparse
import pathlib
import re
import shlex
import subprocess
import sys


ERROR_RE = re.compile(r"\*\*\*\* (.*)")


def shell_join(argv: list[str]) -> str:
    return " ".join(shlex.quote(arg) for arg in argv)


def read_source_lines(path: pathlib.Path) -> list[str]:
    try:
        return path.read_text(errors="replace").splitlines()
    except OSError:
        return []


def find_source_line(source_lines: list[str], text: str) -> int | None:
    needle = text.strip()
    if not needle:
        return None
    for lineno, line in enumerate(source_lines, 1):
        if line.strip() == needle:
            return lineno
    return None


def classify_next_step(reason: str, text: str) -> str:
    stripped = text.strip()
    if "open failure on include file" in reason:
        return "add self-host include shims or an optional preprocessing mode"
    if stripped.startswith("#include"):
        return "add self-host include path/shims or preprocessing before compiling compiler sources"
    if stripped.startswith("#define"):
        return "add enough macro preprocessing for compiler implementation sources"
    if stripped.startswith("#ifdef") or stripped.startswith("#ifndef") or stripped.startswith("#if"):
        return "add conditional preprocessing for compiler implementation sources"
    if stripped.startswith("#undef"):
        return "add #undef support or hide host-only remapping from self-host inputs"
    if stripped.startswith("static "):
        return "add static declaration/function parsing"
    if "global symbol table overflow" in reason:
        return "increase symbol capacity or avoid importing the full prototype list during smoke"
    if "already defined" in reason:
        return "improve symbol/prototype handling after preprocessing/include blockers"
    if "illegal function or declaration" in reason:
        return "extend declaration parser for this source construct"
    if "struct initializer" in reason or stripped.find("= {") >= 0:
        return "add complex/global initializer support"
    return "inspect unsupported source construct and add the smallest frontend support"


def first_error(stderr: str, source_lines: list[str]) -> dict[str, object] | None:
    lines = stderr.splitlines()
    for index, line in enumerate(lines):
        match = ERROR_RE.search(line)
        if not match:
            continue

        text = ""
        if index >= 2:
            text = lines[index - 2]
        if text.strip().startswith("****") and index >= 1:
            text = lines[index - 1]

        reason = match.group(1).strip()
        lineno = find_source_line(source_lines, text)
        return {
            "reason": reason,
            "text": text,
            "line": lineno,
            "next": classify_next_step(reason, text),
        }
    return None


def write_log(
    log_path: pathlib.Path,
    argv: list[str],
    proc: subprocess.CompletedProcess[str],
) -> None:
    with log_path.open("w") as log:
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


def text_or_empty(value: str | bytes | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("latin-1", errors="replace")
    return value


def compile_source(
    compiler: pathlib.Path,
    include_dirs: list[pathlib.Path],
    timeout_seconds: int,
    build_dir: pathlib.Path,
    source: pathlib.Path,
) -> dict[str, object]:
    name = source.stem
    asm_path = build_dir / f"{name}.asm"
    log_path = build_dir / f"{name}.log"
    argv = [str(compiler)]
    for include_dir in include_dirs:
        argv.extend(["-I", str(include_dir)])
    argv.append(str(source))
    timed_out = False
    try:
        proc = subprocess.run(
            argv,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout_seconds,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        timed_out = True
        proc = subprocess.CompletedProcess(
            argv,
            124,
            stdout=text_or_empty(exc.stdout),
            stderr=text_or_empty(exc.stderr),
        )
    asm_path.write_text(proc.stdout)
    write_log(log_path, argv, proc)

    source_lines = read_source_lines(source)
    err = first_error(proc.stderr, source_lines)
    ok = proc.returncode == 0 and err is None
    if timed_out:
        err = {
            "reason": f"compiler timed out after {timeout_seconds}s",
            "text": "",
            "line": None,
            "next": "inspect the partial log for the next parser/preprocessor non-progress case",
        }
        ok = False
    if proc.returncode != 0 and err is None:
        err = {
            "reason": f"compiler exited with status {proc.returncode}",
            "text": "",
            "line": None,
            "next": "inspect compiler log for the first unsupported source construct",
        }

    return {
        "name": name,
        "source": source,
        "asm": asm_path,
        "log": log_path,
        "ok": ok,
        "error": err,
    }


def write_report(report_path: pathlib.Path, args: argparse.Namespace, results: list[dict[str, object]]) -> None:
    with report_path.open("w") as report:
        report.write("Self-host smoke report\n")
        report.write(f"Compiler: {args.compiler}\n")
        if args.include_dir:
            report.write("Include dirs: " + ", ".join(str(path) for path in args.include_dir) + "\n")
        report.write(f"Strict: {'yes' if args.strict else 'no'}\n")
        report.write("\n")
        for result in results:
            name = result["name"]
            status = "PASS" if result["ok"] else "FAIL"
            report.write(f"{name}: {status}\n")
            report.write(f"  source: {result['source']}\n")
            report.write(f"  asm: {result['asm']}\n")
            report.write(f"  log: {result['log']}\n")
            if not result["ok"]:
                err = result["error"]
                if isinstance(err, dict):
                    report.write(f"  reason: {err.get('reason', 'unknown')}\n")
                    if err.get("line") is not None:
                        report.write(f"  line: {err['line']}\n")
                    if err.get("text"):
                        report.write(f"  text: {err['text']}\n")
                    report.write(f"  next: {err.get('next', 'inspect compiler log')}\n")
            report.write("\n")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=pathlib.Path, required=True)
    parser.add_argument("--build-dir", type=pathlib.Path, required=True)
    parser.add_argument("--include-dir", action="append", default=[], type=pathlib.Path)
    parser.add_argument("--timeout-seconds", default=10, type=int)
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("sources", nargs="+", type=pathlib.Path)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    args.build_dir.mkdir(parents=True, exist_ok=True)

    results = []
    for source in args.sources:
        result = compile_source(
            args.compiler,
            args.include_dir,
            args.timeout_seconds,
            args.build_dir,
            source,
        )
        results.append(result)
        if result["ok"]:
            print(f"{result['name']}: PASS")
        else:
            err = result["error"]
            reason = "unknown"
            if isinstance(err, dict):
                reason = str(err.get("reason", "unknown"))
            print(f"{result['name']}: FAIL {reason}")

    report_path = args.build_dir / "report.txt"
    write_report(report_path, args, results)
    print(f"report: {report_path}")

    if args.strict:
        for result in results:
            if not result["ok"]:
                return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

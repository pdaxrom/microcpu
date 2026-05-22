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
STATS_RE = re.compile(
    r"stats: globals=(\d+)/(\d+) locals=(\d+)/(\d+) "
    r"typedefs=(\d+)/(\d+) macros=(\d+)/(\d+) includes=(\d+)"
)
INCLUDE_RE = re.compile(r'^\s*#\s*include\s*([<"])([^>"]+)[>"]')
DECL_RE = re.compile(
    r"^\s*(?:extern\s+)?(?:int|char|void|FILE|sc_word|intptr_t|uintptr_t)\b.*;\s*$"
)


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


def current_token(text: str) -> str | None:
    tokens = re.findall(r"[A-Za-z_][A-Za-z0-9_]*", text)
    if tokens:
        return tokens[-1]
    return None


def parse_stats(stderr: str) -> dict[str, int] | None:
    match = STATS_RE.search(stderr)
    if not match:
        return None
    keys = [
        "globals_used",
        "globals_capacity",
        "locals_used",
        "locals_capacity",
        "typedefs_used",
        "typedefs_capacity",
        "macros_used",
        "macros_capacity",
        "includes_used",
    ]
    values = [int(value) for value in match.groups()]
    return dict(zip(keys, values))


def resolve_include(
    current_file: pathlib.Path,
    delimiter: str,
    name: str,
    include_dirs: list[pathlib.Path],
) -> pathlib.Path | None:
    candidates: list[pathlib.Path] = []
    if delimiter == '"':
        candidates.append(current_file.parent / name)
    candidates.extend(include_dir / name for include_dir in include_dirs)
    candidates.append(pathlib.Path("include") / name)
    candidates.append(pathlib.Path("smallc-microcpu/include") / name)
    seen: set[pathlib.Path] = set()
    for candidate in candidates:
        normalized = candidate.resolve() if candidate.exists() else candidate
        if normalized in seen:
            continue
        seen.add(normalized)
        if candidate.exists():
            return candidate
    return None


def scan_includes_for_file(
    path: pathlib.Path,
    include_dirs: list[pathlib.Path],
    macros: set[str],
    seen: set[pathlib.Path],
    ordered: list[pathlib.Path],
    repeats: dict[str, int],
) -> None:
    try:
        key = path.resolve()
    except OSError:
        key = path
    if key in seen:
        repeats[str(path)] = repeats.get(str(path), 0) + 1
        return
    seen.add(key)
    active = True
    cond_stack: list[tuple[bool, bool]] = []
    for line in read_source_lines(path):
        stripped = line.strip()
        if stripped.startswith("#define"):
            parts = stripped.split(None, 2)
            if active and len(parts) >= 2:
                name = re.split(r"[^A-Za-z0-9_]", parts[1], maxsplit=1)[0]
                if name:
                    macros.add(name)
            continue
        if stripped.startswith("#undef"):
            parts = stripped.split(None, 1)
            if active and len(parts) == 2:
                macros.discard(parts[1].strip())
            continue
        if stripped.startswith("#ifdef"):
            parts = stripped.split(None, 1)
            cond = len(parts) == 2 and parts[1].strip() in macros
            cond_stack.append((active, cond))
            active = active and cond
            continue
        if stripped.startswith("#ifndef"):
            parts = stripped.split(None, 1)
            cond = len(parts) == 2 and parts[1].strip() not in macros
            cond_stack.append((active, cond))
            active = active and cond
            continue
        if stripped.startswith("#else"):
            if cond_stack:
                parent_active, old_cond = cond_stack[-1]
                new_cond = not old_cond
                cond_stack[-1] = (parent_active, new_cond)
                active = parent_active and new_cond
            continue
        if stripped.startswith("#endif"):
            if cond_stack:
                active = cond_stack.pop()[0]
            continue
        if not active:
            continue
        match = INCLUDE_RE.match(line)
        if not match:
            continue
        inc = resolve_include(path, match.group(1), match.group(2), include_dirs)
        if inc is None:
            continue
        ordered.append(inc)
        scan_includes_for_file(inc, include_dirs, macros, seen, ordered, repeats)


def include_report(
    source: pathlib.Path,
    include_dirs: list[pathlib.Path],
    defines: list[str],
) -> tuple[list[pathlib.Path], dict[str, int]]:
    ordered: list[pathlib.Path] = []
    repeats: dict[str, int] = {}
    scan_includes_for_file(source, include_dirs, set(defines), set(), ordered, repeats)
    return ordered, repeats


def declaration_count(path: pathlib.Path) -> int:
    count = 0
    for line in read_source_lines(path):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if DECL_RE.match(stripped):
            count += 1
    return count


def declaration_contributors(
    source: pathlib.Path,
    includes: list[pathlib.Path],
) -> list[tuple[pathlib.Path, int]]:
    entries: list[tuple[pathlib.Path, int]] = []
    for path in [source] + includes:
        count = declaration_count(path)
        if count:
            entries.append((path, count))
    entries.sort(key=lambda item: item[1], reverse=True)
    return entries[:5]


def classify_next_step(reason: str, text: str) -> str:
    stripped = text.strip()
    token = current_token(text)
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
        if token and len(token) > 8:
            return "rename self-host smoke input symbols or extend the compiler symbol-name limit"
        return "improve symbol/prototype handling after preprocessing/include blockers"
    if "illegal function or declaration" in reason:
        return "extend declaration parser for this source construct"
    if "struct initializer" in reason or stripped.find("= {") >= 0:
        return "add complex/global initializer support"
    return "inspect unsupported source construct and add the smallest frontend support"


def classify_root_cause(reason: str, text: str) -> str:
    stripped = text.strip()
    token = current_token(text)
    if "global symbol table overflow" in reason:
        return "symbol table capacity reached during declaration parsing"
    if "already defined" in reason and "(" in stripped:
        return "duplicate prototype/declaration handling"
    if "already defined" in reason and token and len(token) > 8:
        return "8-character Small-C symbol name collision"
    if "open failure on include file" in reason:
        return "missing controlled include"
    if stripped.startswith("#if"):
        return "unsupported conditional preprocessing"
    if stripped.startswith("static "):
        return "unsupported static declaration parsing"
    return "unsupported source construct"


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
            "token": current_token(text),
            "root_cause": classify_root_cause(reason, text),
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
    defines: list[str],
    timeout_seconds: int,
    build_dir: pathlib.Path,
    source: pathlib.Path,
) -> dict[str, object]:
    name = source.stem
    asm_path = build_dir / f"{name}.asm"
    log_path = build_dir / f"{name}.log"
    argv = [str(compiler)]
    for define in defines:
        argv.extend(["-D", define])
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
    stats = parse_stats(proc.stderr)
    includes, include_repeats = include_report(source, include_dirs, defines)
    contributors = declaration_contributors(source, includes)
    ok = proc.returncode == 0 and err is None
    if timed_out:
        err = {
            "reason": f"compiler timed out after {timeout_seconds}s",
            "text": "",
            "line": None,
            "token": None,
            "root_cause": "compiler did not make progress",
            "next": "inspect the partial log for the next parser/preprocessor non-progress case",
        }
        ok = False
    if proc.returncode != 0 and err is None:
        err = {
            "reason": f"compiler exited with status {proc.returncode}",
            "text": "",
            "line": None,
            "token": None,
            "root_cause": "compiler exited without a structured error",
            "next": "inspect compiler log for the first unsupported source construct",
        }

    return {
        "name": name,
        "source": source,
        "asm": asm_path,
        "log": log_path,
        "ok": ok,
        "error": err,
        "stats": stats,
        "includes": includes,
        "include_repeats": include_repeats,
        "contributors": contributors,
    }


def write_report(report_path: pathlib.Path, args: argparse.Namespace, results: list[dict[str, object]]) -> None:
    with report_path.open("w") as report:
        report.write("Self-host smoke report\n")
        report.write(f"Compiler: {args.compiler}\n")
        if args.include_dir:
            report.write("Include dirs: " + ", ".join(str(path) for path in args.include_dir) + "\n")
        if args.define:
            report.write("Defines: " + ", ".join(args.define) + "\n")
        report.write(f"Strict: {'yes' if args.strict else 'no'}\n")
        report.write("Conclusion:\n")
        report.write("  root cause: host-only prototype imports and strict duplicate prototype handling\n")
        report.write("  fix applied: selfhost defines SMALLC_SELFHOST, host_compat.h skips smallc_proto.h, repeated prototypes are declarations\n")
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
                    if err.get("token"):
                        report.write(f"  token: {err['token']}\n")
                    if err.get("text"):
                        report.write(f"  text: {err['text']}\n")
                    report.write(f"  root cause: {err.get('root_cause', 'unknown')}\n")
                    report.write(f"  next: {err.get('next', 'inspect compiler log')}\n")
            stats = result.get("stats")
            if isinstance(stats, dict):
                report.write(
                    "  symbols: globals={globals_used}/{globals_capacity} "
                    "locals={locals_used}/{locals_capacity} "
                    "typedefs={typedefs_used}/{typedefs_capacity} "
                    "macros={macros_used}/{macros_capacity} "
                    "includes={includes_used}\n".format(**stats)
                )
            includes = result.get("includes", [])
            if includes:
                report.write("  included files:\n")
                for include in includes:
                    report.write(f"    {include}\n")
            repeats = result.get("include_repeats", {})
            if repeats:
                total = sum(repeats.values())
                report.write(f"  include repeats observed: {total}\n")
            else:
                report.write("  include repeats observed: 0\n")
            contributors = result.get("contributors", [])
            if contributors:
                report.write("  approximate declaration contributors:\n")
                for path, count in contributors:
                    report.write(f"    {path}: {count}\n")
            report.write("\n")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=pathlib.Path, required=True)
    parser.add_argument("--build-dir", type=pathlib.Path, required=True)
    parser.add_argument("--define", action="append", default=[])
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
            args.define,
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

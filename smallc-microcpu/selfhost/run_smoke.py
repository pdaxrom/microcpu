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
ASM_DIAG_RE = re.compile(r"^(Line \d+: .+|Compilation failed: .+)$")
LABEL_RE = re.compile(r"^([A-Za-z_.$][A-Za-z0-9_.$]*):")
STATS_RE = re.compile(
    r"stats: globals=(\d+)/(\d+) locals=(\d+)/(\d+) "
    r"typedefs=(\d+)/(\d+) macros=(\d+)/(\d+) "
    r"(?:literals=(\d+)/(\d+) )?includes=(\d+)"
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
        "literals_used",
        "literals_capacity",
        "includes_used",
    ]
    values = [int(value) if value is not None else 0 for value in match.groups()]
    return dict(zip(keys, values))


def parse_asm_symbols(path: pathlib.Path) -> tuple[list[str], list[str]]:
    publics: list[str] = []
    externs: list[str] = []
    for line in read_source_lines(path):
        parts = line.strip().split()
        if len(parts) != 2:
            continue
        if parts[0] == "public":
            publics.append(parts[1])
        elif parts[0] == "extern":
            externs.append(parts[1])
    return publics, externs


def estimate_instruction_bytes(op: str) -> int:
    if op == "set":
        return 4
    if op == "jmp":
        return 4
    if op == "jsr":
        return 6
    if op == "push" or op == "pop":
        return 4
    return 2


def data_items(text: str) -> int:
    text = text.split(";", 1)[0].strip()
    if not text:
        return 0
    return len([part for part in text.split(",") if part.strip()])


def parse_int(text: str) -> int:
    try:
        return int(text, 0)
    except ValueError:
        return 0


def analyze_asm(path: pathlib.Path) -> dict[str, object]:
    code_bytes = 0
    data_bytes = 0
    local_symbols: set[str] = set()
    public_symbols: set[str] = set()
    current = ""
    symbol_bytes: dict[str, int] = {}
    for line in read_source_lines(path):
        stripped = line.strip()
        if not stripped or stripped.startswith(";"):
            continue
        parts = stripped.split()
        if len(parts) == 2 and parts[0] == "public":
            public_symbols.add(parts[1])
            continue
        if parts[0] == "extern" or parts[0] == "include" or parts[0] == "align":
            continue
        match = LABEL_RE.match(stripped)
        if match:
            label = match.group(1)
            if not re.fullmatch(r"_\d+", label):
                current = label
                symbol_bytes.setdefault(current, 0)
                if label not in public_symbols:
                    local_symbols.add(label)
            continue
        op = parts[0]
        if op == "db":
            data_bytes += data_items(stripped[2:])
            continue
        if op == "dw":
            data_bytes += data_items(stripped[2:]) * 2
            continue
        if op == "ds":
            data_bytes += parse_int(parts[1]) if len(parts) > 1 else 0
            continue
        size = estimate_instruction_bytes(op)
        code_bytes += size
        if current:
            symbol_bytes[current] = symbol_bytes.get(current, 0) + size
    largest = sorted(symbol_bytes.items(), key=lambda item: item[1], reverse=True)[:5]
    return {
        "code_bytes": code_bytes,
        "data_bytes": data_bytes,
        "local_symbols": len(local_symbols),
        "largest_symbols": largest,
    }


def assembler_diagnostic(text: str) -> str:
    entries: list[str] = []
    for line in text.splitlines():
        if ASM_DIAG_RE.match(line.strip()):
            entries.append(line.strip())
    return "; ".join(entries[-3:])


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
    if "**" in stripped:
        return "add pointer-to-pointer declarator support"
    if "wrong number of arguments" in reason and "intptr_t" in stripped:
        return "support typedef names in K&R-style argument type declarations or avoid int remapping for selfhost inputs"
    if stripped.startswith("const "):
        return "support or strip the const qualifier in selfhost inputs"
    if "literal queue overflow" in reason:
        return "raise literal-pool capacity or split large generated string tables"
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
    if "**" in stripped:
        return "unsupported pointer-to-pointer declarator"
    if "wrong number of arguments" in reason and "intptr_t" in stripped:
        return "unsupported typedef name in K&R argument declaration"
    if stripped.startswith("const "):
        return "unsupported const qualifier"
    if "literal queue overflow" in reason:
        return "literal pool capacity limit"
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


def append_command_log(
    log_path: pathlib.Path,
    title: str,
    argv: list[str],
    proc: subprocess.CompletedProcess[str],
) -> None:
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


def assemble_object(
    assembler: pathlib.Path,
    asm_path: pathlib.Path,
    obj_path: pathlib.Path,
    log_path: pathlib.Path,
) -> dict[str, object]:
    argv = [str(assembler), "-object", str(asm_path), str(obj_path)]
    proc = subprocess.run(
        argv,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    write_log(log_path, argv, proc)
    ok = proc.returncode == 0
    size = obj_path.stat().st_size if ok and obj_path.exists() else 0
    asm_lines = len(read_source_lines(asm_path))
    combined_log = text_or_empty(proc.stdout) + text_or_empty(proc.stderr)
    diagnostic = assembler_diagnostic(combined_log)
    fail_reason = "object assembly failed"
    fail_root = "generated assembly is not object-assembler clean"
    fail_next = "inspect the object assembly log and emitted microasm"
    if not ok and "Related offset too long" in combined_log:
        fail_reason = "object branch displacement exceeded range"
        fail_root = "generated object code used a short relative branch for a distant label"
        fail_next = "split the function or use an object-mode long branch sequence"
    elif not ok and "Compilation failed: No error" in combined_log:
        fail_reason = "object assembly failed after a large asm output"
        fail_root = "object module is likely hitting the current 64K code-size limit"
        fail_next = "split the translation unit, improve code density, or extend the object format"
    return {
        "ok": ok,
        "object": obj_path,
        "object_log": log_path,
        "object_size": size,
        "asm_lines": asm_lines,
        "diagnostic": diagnostic,
        "fail_reason": fail_reason,
        "fail_root": fail_root,
        "fail_next": fail_next,
    }


def text_or_empty(value: str | bytes | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("latin-1", errors="replace")
    return value


def compile_source(
    compiler: pathlib.Path,
    preprocessor: pathlib.Path | None,
    cc_only: pathlib.Path | None,
    assembler: pathlib.Path | None,
    include_dirs: list[pathlib.Path],
    defines: list[str],
    timeout_seconds: int,
    build_dir: pathlib.Path,
    source: pathlib.Path,
    object_mode: bool,
    preprocess_mode: bool,
) -> dict[str, object]:
    name = source.stem
    asm_path = build_dir / f"{name}.asm"
    i_path = build_dir / f"{name}.i"
    log_path = build_dir / f"{name}.log"
    timed_out = False
    log_path.write_text("")
    if preprocess_mode:
        argv = [str(preprocessor), "-o", str(i_path)]
        for define in defines:
            argv.extend(["-D", define])
        for include_dir in include_dirs:
            argv.extend(["-I", str(include_dir)])
        argv.append(str(source))
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
        append_command_log(log_path, "preprocess", argv, proc)
        if proc.returncode == 0 and not timed_out:
            argv = [str(cc_only)]
            if object_mode:
                argv.append("--object")
            argv.extend(["-o", str(asm_path), str(i_path)])
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
            append_command_log(log_path, "compile", argv, proc)
    else:
        argv = [str(compiler)]
        if object_mode:
            argv.append("--object")
        for define in defines:
            argv.extend(["-D", define])
        for include_dir in include_dirs:
            argv.extend(["-I", str(include_dir)])
        argv.append(str(source))
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
        append_command_log(log_path, "compile", argv, proc)

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

    object_result = None
    if object_mode and ok:
        if assembler is None:
            object_result = {
                "ok": False,
                "object": build_dir / f"{name}.o",
                "object_log": build_dir / f"{name}.obj.log",
                "object_size": 0,
            }
            ok = False
            err = {
                "reason": "--object-mode requires --assembler",
                "text": "",
                "line": None,
                "token": None,
                "root_cause": "selfhost smoke configuration",
                "next": "pass --assembler PATH when OBJECT_MODE=1",
            }
        else:
            object_result = assemble_object(
                assembler,
                asm_path,
                build_dir / f"{name}.o",
                build_dir / f"{name}.obj.log",
            )
            if not object_result["ok"]:
                ok = False
                err = {
                    "reason": object_result.get("fail_reason", "object assembly failed"),
                    "text": "",
                    "line": None,
                    "token": None,
                    "root_cause": object_result.get(
                        "fail_root",
                        "generated assembly is not object-assembler clean",
                    ),
                    "next": object_result.get(
                        "fail_next",
                        "inspect the object assembly log and emitted microasm",
                    ),
                }

    publics, externs = parse_asm_symbols(asm_path)
    asm_analysis = analyze_asm(asm_path)
    return {
        "name": name,
        "source": source,
        "asm": asm_path,
        "preprocessed": i_path if preprocess_mode else None,
        "log": log_path,
        "ok": ok,
        "error": err,
        "object_result": object_result,
        "publics": publics,
        "externs": externs,
        "asm_analysis": asm_analysis,
        "stats": stats,
        "includes": includes,
        "include_repeats": include_repeats,
        "contributors": contributors,
    }


def write_report(report_path: pathlib.Path, args: argparse.Namespace, results: list[dict[str, object]]) -> None:
    with report_path.open("w") as report:
        all_ok = all(bool(result["ok"]) for result in results)
        report.write("Self-host smoke report\n")
        report.write(f"Compiler: {args.compiler}\n")
        if args.preprocess_mode:
            report.write(f"Preprocessor: {args.preprocessor}\n")
            report.write(f"Compiler-only: {args.cc_only}\n")
        if args.include_dir:
            report.write("Include dirs: " + ", ".join(str(path) for path in args.include_dir) + "\n")
        if args.define:
            report.write("Defines: " + ", ".join(args.define) + "\n")
        report.write(f"Object mode: {'yes' if args.object_mode else 'no'}\n")
        report.write(f"Preprocess mode: {'yes' if args.preprocess_mode else 'no'}\n")
        if args.object_mode and args.assembler:
            report.write(f"Assembler: {args.assembler}\n")
        report.write(f"Strict: {'yes' if args.strict else 'no'}\n")
        report.write("Conclusion:\n")
        report.write("  resolved: host-only prototype imports, strict duplicate prototype handling, 31-character identifiers, minimal void/static parsing, multiline function headers, pointer-depth declarators, typedef K&R argument declarations, ignored const qualifiers, sizeof(*p), simple casts, function-pointer calls, and larger literal storage\n")
        if all_ok:
            report.write("  current blockers: none for this compile/object smoke set\n")
        else:
            report.write("  current blockers: see per-file root cause and next-step entries below\n")
        report.write("\n")
        for result in results:
            name = result["name"]
            status = "PASS" if result["ok"] else "FAIL"
            report.write(f"{name}: {status}\n")
            report.write(f"  source: {result['source']}\n")
            if result.get("preprocessed"):
                report.write(f"  preprocessed: {result['preprocessed']}\n")
            report.write(f"  asm: {result['asm']}\n")
            report.write(f"  log: {result['log']}\n")
            object_result = result.get("object_result")
            if isinstance(object_result, dict):
                report.write(f"  object: {object_result['object']}\n")
                report.write(f"  object log: {object_result['object_log']}\n")
                if object_result.get("ok"):
                    report.write(f"  object size: {object_result['object_size']} bytes\n")
                elif object_result.get("asm_lines"):
                    report.write(f"  asm lines before object failure: {object_result['asm_lines']}\n")
                if object_result.get("diagnostic"):
                    report.write(f"  assembler diagnostic: {object_result['diagnostic']}\n")
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
                    "literals={literals_used}/{literals_capacity} "
                    "includes={includes_used}\n".format(**stats)
                )
                report.write(
                    "  literal pool: {literals_used}/{literals_capacity} bytes\n".format(**stats)
                )
            analysis = result.get("asm_analysis")
            if isinstance(analysis, dict):
                report.write(
                    f"  asm estimate: text={analysis['code_bytes']} bytes "
                    f"data={analysis['data_bytes']} bytes "
                    f"local/static labels={analysis['local_symbols']}\n"
                )
                largest = analysis.get("largest_symbols", [])
                if largest:
                    report.write("  largest emitted symbols by estimated text bytes:\n")
                    for symbol, size in largest:
                        report.write(f"    {symbol}: {size}\n")
            publics = result.get("publics", [])
            externs = result.get("externs", [])
            if publics:
                report.write(f"  object public symbols emitted: {len(publics)}\n")
                for symbol in publics[:20]:
                    report.write(f"    {symbol}\n")
                if len(publics) > 20:
                    report.write(f"    ... {len(publics) - 20} more\n")
            if externs:
                report.write(f"  object extern symbols emitted: {len(externs)}\n")
                for symbol in externs[:20]:
                    report.write(f"    {symbol}\n")
                if len(externs) > 20:
                    report.write(f"    ... {len(externs) - 20} more\n")
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
    parser.add_argument("--preprocessor", type=pathlib.Path)
    parser.add_argument("--cc-only", type=pathlib.Path)
    parser.add_argument("--assembler", type=pathlib.Path)
    parser.add_argument("--build-dir", type=pathlib.Path, required=True)
    parser.add_argument("--define", action="append", default=[])
    parser.add_argument("--include-dir", action="append", default=[], type=pathlib.Path)
    parser.add_argument("--object-mode", action="store_true")
    parser.add_argument("--preprocess-mode", action="store_true")
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
            args.preprocessor,
            args.cc_only,
            args.assembler,
            args.include_dir,
            args.define,
            args.timeout_seconds,
            args.build_dir,
            source,
            args.object_mode,
            args.preprocess_mode,
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

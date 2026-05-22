#!/usr/bin/env python3
"""Report-only link smoke for p-code-hosted Small-C tools."""

from __future__ import annotations

import argparse
import pathlib
import re
import shlex
import subprocess
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))

import pcode_merge  # noqa: E402
import pcode_opt  # noqa: E402
import run_pcode_microemu as pcode  # noqa: E402


UNRESOLVED_RE = re.compile(r"(?:unresolved|undefined).*?([A-Za-z_.$][A-Za-z0-9_.$]*)", re.IGNORECASE)
UNRESOLVED_COLON_RE = re.compile(r"(?:unresolved|undefined).*?:\s*([A-Za-z_.$][A-Za-z0-9_.$]*)", re.IGNORECASE)


def shell_join(argv: list[str]) -> str:
    return " ".join(shlex.quote(arg) for arg in argv)


def run_cmd(log_path: pathlib.Path, title: str, argv: list[str]) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
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
    return proc


def extract_unresolved(text: str) -> list[str]:
    values: list[str] = []
    seen: set[str] = set()
    for line in text.splitlines():
        match = UNRESOLVED_COLON_RE.search(line)
        if match is None:
            match = UNRESOLVED_RE.search(line)
        if match:
            name = match.group(1)
            if name not in seen:
                seen.add(name)
                values.append(name)
    return values


def classify_failure(text: str, unresolved: list[str], missing: list[pathlib.Path]) -> str:
    if missing:
        return "missing p-code modules"
    if "Output buffer overflow" in text:
        return "code/data size overflow"
    if unresolved:
        return "unresolved symbols"
    if "already defined" in text or "duplicate" in text.lower():
        return "object symbol collision"
    if "relocation" in text.lower():
        return "p-code relocation unsupported"
    if text:
        return "linker failed"
    return "other"


def write_hosted_stubs(path: pathlib.Path, funcs: list[str], data: list[str]) -> None:
    lines = [
        "; generated hosted stubs for p-code selfhost link smoke",
        "; These are link-only placeholders, not functional target-hosted I/O.",
        "include ../../../../asm/include/pseudo.inc",
        "",
    ]
    for name in funcs:
        lines.append(f"public {name}")
    for name in data:
        lines.append(f"public {name}")
    lines.append("")
    for name in funcs:
        lines.extend([
            f"{name}:",
            "\tclr\tv0",
            "\trts",
        ])
    for name in data:
        lines.extend([
            f"{name}:",
            "\tdw\t0",
        ])
    path.write_text("\n".join(lines) + "\n")


def assemble(args: argparse.Namespace, source: pathlib.Path, obj: pathlib.Path, log: pathlib.Path) -> bool:
    argv = [str(args.assembler), "-object", str(source), str(obj)]
    return run_cmd(log, f"assemble {source.name}", argv).returncode == 0


def link(args: argparse.Namespace, objects: list[pathlib.Path], out: pathlib.Path, log: pathlib.Path) -> subprocess.CompletedProcess[str]:
    argv = [str(args.linker), "-binary", "-o", str(out)]
    argv.extend(str(path) for path in objects)
    return run_cmd(log, "link", argv)


def link_tool(args: argparse.Namespace, name: str, pcas: list[pathlib.Path], interp_obj: pathlib.Path) -> dict[str, object]:
    tool_dir = args.build_dir / name
    tool_dir.mkdir(parents=True, exist_ok=True)
    log = tool_dir / f"{name}.log"
    merged_pca = tool_dir / f"{name}.merged.pca"
    opt_pca = tool_dir / f"{name}.merged.opt.pca"
    pcode_asm = tool_dir / f"{name}.pcode.asm"
    pcode_obj = tool_dir / f"{name}.pcode.o"
    stubs_asm = tool_dir / "hosted_stubs.asm"
    stubs_obj = tool_dir / "hosted_stubs.o"
    bin_path = tool_dir / f"{name}.bin"
    log.write_text("")

    result: dict[str, object] = {
        "name": name,
        "pcas": pcas,
        "missing": [path for path in pcas if not path.exists()],
        "merge_ok": False,
        "pcode_obj_ok": False,
        "stubs_ok": False,
        "link_ok": False,
        "reason": "",
        "log": log,
        "bin": bin_path,
        "bytecode": 0,
        "data": 0,
        "native_table": 0,
        "payload": 0,
        "pcode_obj_size": 0,
        "stubs_size": 0,
        "interpreter_size": interp_obj.stat().st_size if interp_obj.exists() else 0,
        "linked_size": 0,
        "natives": [],
        "extern_data": [],
        "unresolved": [],
        "diagnostic": "",
        "analysis": None,
        "opt_stats": None,
    }

    if result["missing"]:
        result["reason"] = "missing p-code modules"
        return result

    try:
        pcode_merge.merge_pca_files(pcas, merged_pca)
        encode_path = merged_pca
        if args.pcode_opt:
            result["opt_stats"] = pcode_opt.optimize_pca_file(merged_pca, opt_pca)
            encode_path = opt_pca
        result["analysis"] = pcode_opt.analyze_pca(encode_path)
        entry, bytecode, data, data_labels, natives, externs = pcode.encode_pca(encode_path)
        pcode.write_pcode_object_asm(pcode_asm, entry, bytecode, data, data_labels, natives, externs)
        extern_data = [symbol for symbol in externs if symbol not in natives]
        result.update({
            "merge_ok": True,
            "bytecode": pcode.bytecode_size(bytecode),
            "data": len(data),
            "native_table": len(natives) * 2,
            "payload": pcode.bytecode_size(bytecode) + len(data) + len(natives) * 2,
            "natives": natives,
            "extern_data": extern_data,
        })
    except Exception as exc:
        result["reason"] = f"p-code merge/object generation failed: {exc}"
        return result

    if assemble(args, pcode_asm, pcode_obj, log):
        result["pcode_obj_ok"] = True
        result["pcode_obj_size"] = pcode_obj.stat().st_size
    else:
        diagnostic = log.read_text(errors="replace")
        if int(result["payload"]) > 65536:
            result["reason"] = "code/data size overflow"
        else:
            result["reason"] = classify_failure(diagnostic, extract_unresolved(diagnostic), [])
        result["diagnostic"] = diagnostic
        return result

    write_hosted_stubs(stubs_asm, list(result["natives"]), list(result["extern_data"]))
    if assemble(args, stubs_asm, stubs_obj, log):
        result["stubs_ok"] = True
        result["stubs_size"] = stubs_obj.stat().st_size
    else:
        diagnostic = log.read_text(errors="replace")
        result["reason"] = classify_failure(diagnostic, extract_unresolved(diagnostic), [])
        result["diagnostic"] = diagnostic
        return result

    proc = link(args, [interp_obj, stubs_obj, pcode_obj], bin_path, log)
    diagnostic = (proc.stdout or "") + (proc.stderr or "")
    unresolved = extract_unresolved(diagnostic)
    result["diagnostic"] = diagnostic
    result["unresolved"] = unresolved
    if proc.returncode == 0:
        result["link_ok"] = True
        result["linked_size"] = bin_path.stat().st_size if bin_path.exists() else 0
    else:
        result["reason"] = classify_failure(diagnostic, unresolved, [])
    return result


def write_tool_report(fp, result: dict[str, object]) -> None:
    fp.write(f"{result['name']}:\n")
    fp.write("  p-code modules:\n")
    for path in result["pcas"]:
        fp.write(f"    {path.name}\n")
    fp.write(f"  bytecode bytes: {result['bytecode']}\n")
    fp.write(f"  p-code global data bytes: {result['data']}\n")
    fp.write(f"  native table bytes: {result['native_table']}\n")
    fp.write(f"  p-code payload bytes: {result['payload']}\n")
    opt_stats = result["opt_stats"]
    if opt_stats:
        fp.write("  optimizer: enabled\n")
        fp.write(f"  optimizer removed temp store/load pairs: {opt_stats['removed_temp_roundtrips']}\n")
        fp.write(f"  optimizer bytecode before: {opt_stats['bytecode_before']}\n")
        fp.write(f"  optimizer bytecode after: {opt_stats['bytecode_after']}\n")
        fp.write(f"  optimizer bytecode saved: {opt_stats['bytecode_saved']}\n")
    else:
        fp.write("  optimizer: disabled\n")
    analysis = result["analysis"]
    if analysis:
        fp.write("  size diagnostics:\n")
        for line in pcode_opt.format_analysis(analysis, "    "):
            fp.write(f"{line}\n")
    fp.write(f"  interpreter object size: {result['interpreter_size']}\n")
    fp.write(f"  hosted stubs size: {result['stubs_size']}\n")
    fp.write("  libc/runtime size: 0\n")
    fp.write(f"  pcode.o size: {result['pcode_obj_size']}\n")
    fp.write(f"  final linked binary size: {result['linked_size']}\n")
    fp.write(f"  output buffer / 64K status: {'below 64K' if int(result['linked_size']) and int(result['linked_size']) <= 65536 else 'not linked or above 64K'}\n")
    fp.write(f"  link status: {'PASS' if result['link_ok'] else 'FAIL'}\n")
    fp.write(f"  PASS/FAIL: {'PASS' if result['link_ok'] else 'FAIL'}\n")
    if not result["link_ok"]:
        fp.write(f"  failure class: {result['reason']}\n")
    if result["missing"]:
        fp.write("  missing p-code modules:\n")
        for path in result["missing"]:
            fp.write(f"    {path}\n")
    if result["unresolved"]:
        fp.write("  unresolved symbols:\n")
        for symbol in result["unresolved"][:80]:
            fp.write(f"    {symbol}\n")
        if len(result["unresolved"]) > 80:
            fp.write(f"    ... {len(result['unresolved']) - 80} more\n")
    natives = result["natives"]
    if natives:
        fp.write("  native call stubs:\n")
        for symbol in natives[:40]:
            fp.write(f"    {symbol}\n")
        if len(natives) > 40:
            fp.write(f"    ... {len(natives) - 40} more\n")
    extern_data = result["extern_data"]
    if extern_data:
        fp.write("  extern data stubs:\n")
        for symbol in extern_data[:40]:
            fp.write(f"    {symbol}\n")
        if len(extern_data) > 40:
            fp.write(f"    ... {len(extern_data) - 40} more\n")
    diagnostic = result["diagnostic"]
    if diagnostic:
        fp.write("  tool diagnostic:\n")
        for line in diagnostic.splitlines()[-40:]:
            fp.write(f"    {line}\n")
    fp.write(f"  log: {result['log']}\n\n")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assembler", required=True, type=pathlib.Path)
    parser.add_argument("--linker", required=True, type=pathlib.Path)
    parser.add_argument("--runtime-dir", required=True, type=pathlib.Path)
    parser.add_argument("--build-dir", required=True, type=pathlib.Path)
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--pcode-opt", action="store_true")
    parser.add_argument("--smallcpp-pcas", nargs="+", required=True, type=pathlib.Path)
    parser.add_argument("--smallcc-pcas", nargs="+", required=True, type=pathlib.Path)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    args.build_dir.mkdir(parents=True, exist_ok=True)
    report = args.build_dir / "report.txt"
    interp_obj = args.build_dir / "pcode_interpreter.o"
    interp_log = args.build_dir / "pcode_interpreter.log"
    interp_log.write_text("")
    interp_ok = assemble(args, args.runtime_dir / "pcode_interpreter.asm", interp_obj, interp_log)

    results: list[dict[str, object]] = []
    if interp_ok:
        results.append(link_tool(args, "smallcpp", args.smallcpp_pcas, interp_obj))
        results.append(link_tool(args, "smallcc", args.smallcc_pcas, interp_obj))

    all_ok = bool(results) and all(result["link_ok"] for result in results)
    with report.open("w") as fp:
        fp.write("Self-host p-code link smoke report\n")
        fp.write(f"Strict: {'yes' if args.strict else 'no'}\n")
        fp.write(f"Interpreter assembled: {'yes' if interp_ok else 'no'}\n")
        fp.write(f"Status: {'PASS' if all_ok else 'FAIL'}\n")
        fp.write("Hosted stubs are link-only placeholders, not functional target file I/O.\n\n")
        if not interp_ok:
            fp.write(f"pcode_interpreter assembly failed: {interp_log}\n")
        for result in results:
            write_tool_report(fp, result)

    print(f"selfhost-pcode-link-smoke: {'PASS' if all_ok else 'FAIL'}")
    print(f"report: {report}")
    if args.strict and not all_ok:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

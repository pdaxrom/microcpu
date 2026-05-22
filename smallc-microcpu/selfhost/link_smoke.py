#!/usr/bin/env python3
"""Report-only link smoke for self-host compiler objects."""

from __future__ import annotations

import argparse
import pathlib
import re
import shlex
import subprocess
import sys


UNRESOLVED_RE = re.compile(r"(?:unresolved|undefined).*?([A-Za-z_.$][A-Za-z0-9_.$]*)", re.IGNORECASE)
UNRESOLVED_COLON_RE = re.compile(r"(?:unresolved|undefined).*?:\s*([A-Za-z_.$][A-Za-z0-9_.$]*)", re.IGNORECASE)
ESTIMATE_RE = re.compile(r"^\s*asm estimate: text=(\d+) bytes data=(\d+) bytes")


def shell_join(argv: list[str]) -> str:
    return " ".join(shlex.quote(arg) for arg in argv)


def write_command_log(path: pathlib.Path, title: str, argv: list[str], proc: subprocess.CompletedProcess[str]) -> None:
    with path.open("a") as log:
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


def assemble_runtime(args: argparse.Namespace, report_dir: pathlib.Path) -> tuple[bool, list[pathlib.Path]]:
    runtime_dir = report_dir / "__runtime"
    runtime_dir.mkdir(parents=True, exist_ok=True)
    objects: list[pathlib.Path] = []
    ok = True
    for source in [
        args.runtime_dir / "crt0_object.asm",
        args.runtime_dir / "runtime_object.asm",
        args.runtime_dir / "stack_object.asm",
    ]:
        obj = runtime_dir / f"{source.stem}.o"
        log = runtime_dir / f"{source.stem}.log"
        log.write_text("")
        argv = [str(args.assembler), "-object", str(source), str(obj)]
        proc = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
        write_command_log(log, "assemble runtime", argv, proc)
        if proc.returncode == 0:
            objects.append(obj)
        else:
            ok = False
    return ok, objects


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


def load_estimates(report_dir: pathlib.Path) -> dict[str, tuple[int, int]]:
    report = report_dir / "report.txt"
    estimates: dict[str, tuple[int, int]] = {}
    current = ""
    if not report.exists():
        return estimates
    for line in report.read_text().splitlines():
        if line and not line.startswith(" ") and line.endswith(": PASS"):
            current = line.split(":", 1)[0]
            continue
        match = ESTIMATE_RE.match(line)
        if match and current:
            estimates[current] = (int(match.group(1)), int(match.group(2)))
    return estimates


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assembler", type=pathlib.Path, required=True)
    parser.add_argument("--linker", type=pathlib.Path, required=True)
    parser.add_argument("--build-dir", type=pathlib.Path, required=True)
    parser.add_argument("--runtime-dir", type=pathlib.Path, required=True)
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--smallcpp-objects", nargs="+", default=[], type=pathlib.Path)
    parser.add_argument("--smallcc-objects", nargs="+", default=[], type=pathlib.Path)
    parser.add_argument("objects", nargs="*", type=pathlib.Path)
    return parser.parse_args(argv)


def link_program(
    args: argparse.Namespace,
    name: str,
    objects: list[pathlib.Path],
    runtime_objects: list[pathlib.Path],
    report_dir: pathlib.Path,
    estimates: dict[str, tuple[int, int]],
) -> dict[str, object]:
    log = report_dir / f"{name}-link.log"
    bin_path = report_dir / f"{name}.bin"
    log.write_text("")
    missing = [path for path in objects if not path.exists()]
    link_objects: list[pathlib.Path] = []
    if runtime_objects:
        link_objects.append(runtime_objects[0])
    link_objects.extend(objects)
    if len(runtime_objects) > 1:
        link_objects.extend(runtime_objects[1:])
    proc = subprocess.CompletedProcess([], 1, "", "")
    link_ok = False
    if not missing and runtime_objects:
        argv2 = [str(args.linker), "-binary", "-o", str(bin_path)]
        argv2.extend(str(path) for path in link_objects)
        proc = subprocess.run(argv2, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
        write_command_log(log, f"link {name}", argv2, proc)
        link_ok = proc.returncode == 0
    combined = (proc.stdout or "") + (proc.stderr or "")
    unresolved = extract_unresolved(combined)
    est_text = 0
    est_data = 0
    largest = sorted(objects, key=lambda path: path.stat().st_size if path.exists() else 0, reverse=True)
    for path in objects:
        if path.stem in estimates:
            est_text += estimates[path.stem][0]
            est_data += estimates[path.stem][1]
    reason = ""
    if not link_ok:
        reason = "linker failed"
        if missing:
            reason = "missing objects"
        elif "Output buffer overflow" in combined:
            reason = "linked image exceeds current linker output buffer"
        elif unresolved:
            reason = "unresolved external symbols"
    return {
        "name": name,
        "objects": objects,
        "missing": missing,
        "ok": link_ok,
        "log": log,
        "bin": bin_path,
        "combined": combined,
        "unresolved": unresolved,
        "reason": reason,
        "size": bin_path.stat().st_size if link_ok and bin_path.exists() else 0,
        "est_text": est_text,
        "est_data": est_data,
        "largest": largest[:5],
    }


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    args.build_dir.mkdir(parents=True, exist_ok=True)
    report = args.build_dir / "link-report.txt"
    runtime_ok, runtime_objects = assemble_runtime(args, args.build_dir)
    estimates = load_estimates(args.build_dir)

    programs: list[tuple[str, list[pathlib.Path]]] = []
    if args.smallcpp_objects:
        programs.append(("smallcpp", args.smallcpp_objects))
    if args.smallcc_objects:
        programs.append(("smallcc", args.smallcc_objects))
    if not programs and args.objects:
        programs.append(("combined", args.objects))

    results = [
        link_program(args, name, objects, runtime_objects if runtime_ok else [], args.build_dir, estimates)
        for name, objects in programs
    ]
    link_ok = bool(results) and all(result["ok"] for result in results)

    with report.open("w") as fp:
        fp.write("Self-host link smoke report\n")
        fp.write(f"Strict: {'yes' if args.strict else 'no'}\n")
        fp.write(f"Status: {'PASS' if link_ok else 'FAIL'}\n")
        fp.write(f"Runtime objects assembled: {'yes' if runtime_ok else 'no'}\n")
        if not programs:
            fp.write("Reason: no program object groups were provided\n")
        for result in results:
            fp.write("\n")
            fp.write(f"{result['name']}:\n")
            fp.write(f"  objects: {len(result['objects'])}\n")
            fp.write(f"  estimated text bytes: {result['est_text']}\n")
            fp.write(f"  estimated data bytes: {result['est_data']}\n")
            fp.write(f"  status: {'PASS' if result['ok'] else 'FAIL'}\n")
            fp.write(f"  log: {result['log']}\n")
            fp.write(f"  output: {result['bin']}\n")
            if result["ok"]:
                fp.write(f"  linked image size: {result['size']} bytes\n")
                fp.write(f"  below 64K: {'yes' if result['size'] <= 65536 else 'no'}\n")
            else:
                fp.write(f"  reason: {result['reason']}\n")
            largest = result["largest"]
            if largest:
                fp.write("  largest objects:\n")
                for path in largest:
                    size = path.stat().st_size if path.exists() else 0
                    fp.write(f"    {path.name}: {size} bytes\n")
            if result["missing"]:
                fp.write("  missing objects:\n")
                for path in result["missing"]:
                    fp.write(f"    {path}\n")
            unresolved = result["unresolved"]
            if unresolved:
                fp.write("  unresolved externs:\n")
                for name in unresolved[:80]:
                    fp.write(f"    {name}\n")
                if len(unresolved) > 80:
                    fp.write(f"    ... {len(unresolved) - 80} more\n")
            combined = result["combined"]
            if combined:
                fp.write("  linker diagnostic:\n")
                for line in combined.splitlines()[-40:]:
                    fp.write(f"    {line}\n")

    print(f"selfhost-link-smoke: {'PASS' if link_ok else 'FAIL'}")
    print(f"report: {report}")
    if args.strict and not link_ok:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

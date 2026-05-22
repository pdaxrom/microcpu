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
    for match in UNRESOLVED_RE.finditer(text):
        name = match.group(1)
        if name not in seen:
            seen.add(name)
            values.append(name)
    return values


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assembler", type=pathlib.Path, required=True)
    parser.add_argument("--linker", type=pathlib.Path, required=True)
    parser.add_argument("--build-dir", type=pathlib.Path, required=True)
    parser.add_argument("--runtime-dir", type=pathlib.Path, required=True)
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("objects", nargs="+", type=pathlib.Path)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    args.build_dir.mkdir(parents=True, exist_ok=True)
    report = args.build_dir / "link-report.txt"
    log = args.build_dir / "link.log"
    bin_path = args.build_dir / "selfhost-link.bin"
    log.write_text("")

    missing = [path for path in args.objects if not path.exists()]
    runtime_ok, runtime_objects = assemble_runtime(args, args.build_dir)
    link_objects = []
    if runtime_objects:
        link_objects.append(runtime_objects[0])
    link_objects.extend(args.objects)
    if len(runtime_objects) > 1:
        link_objects.extend(runtime_objects[1:])

    link_ok = False
    proc = subprocess.CompletedProcess([], 1, "", "")
    if not missing and runtime_ok:
        argv2 = [str(args.linker), "-binary", "-o", str(bin_path)]
        argv2.extend(str(path) for path in link_objects)
        proc = subprocess.run(argv2, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
        write_command_log(log, "link selfhost", argv2, proc)
        link_ok = proc.returncode == 0

    combined = (proc.stdout or "") + (proc.stderr or "")
    unresolved = extract_unresolved(combined)
    with report.open("w") as fp:
        fp.write("Self-host link smoke report\n")
        fp.write(f"Strict: {'yes' if args.strict else 'no'}\n")
        fp.write(f"Status: {'PASS' if link_ok else 'FAIL'}\n")
        fp.write(f"Log: {log}\n")
        fp.write(f"Output: {bin_path}\n")
        fp.write(f"Compiler objects: {len(args.objects)}\n")
        if missing:
            fp.write("Missing objects:\n")
            for path in missing:
                fp.write(f"  {path}\n")
        fp.write(f"Runtime objects assembled: {'yes' if runtime_ok else 'no'}\n")
        if link_ok and bin_path.exists():
            fp.write(f"Linked image size: {bin_path.stat().st_size} bytes\n")
        if not link_ok:
            reason = "linker failed"
            if "Output buffer overflow" in combined:
                reason = "linked compiler image exceeds current linker output buffer"
            elif unresolved:
                reason = "unresolved external symbols"
            fp.write(f"Reason: {reason}\n")
        if unresolved:
            fp.write("Unresolved externs:\n")
            for name in unresolved[:80]:
                fp.write(f"  {name}\n")
            if len(unresolved) > 80:
                fp.write(f"  ... {len(unresolved) - 80} more\n")
        if combined:
            fp.write("Linker diagnostic:\n")
            for line in combined.splitlines()[-40:]:
                fp.write(f"  {line}\n")

    print(f"selfhost-link-smoke: {'PASS' if link_ok else 'FAIL'}")
    print(f"report: {report}")
    if args.strict and not link_ok:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Run split p-code selfhost images far enough to exercise hosted I/O."""

from __future__ import annotations

import argparse
import pathlib
import re
import shlex
import subprocess
import sys


REG_RE = re.compile(r"\b(?:v0|r3)=([0-9a-fA-F]{4})\b")
HEAP_OVERFLOW = 0xCA10
HEAP_LIMIT = 0xFDE0


def shell_join(argv: list[str]) -> str:
    return " ".join(shlex.quote(arg) for arg in argv)


def text_or_empty(value: bytes | str | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("latin-1", errors="replace")
    return value


def run_cmd(log_path: pathlib.Path, title: str, argv: list[str], binary: bool = False) -> subprocess.CompletedProcess:
    if binary:
        proc = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    else:
        proc = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
    with log_path.open("a") as log:
        log.write(f"== {title} ==\n")
        log.write(f"$ {shell_join(argv)}\n")
        log.write(f"exit={proc.returncode}\n")
        stdout = text_or_empty(proc.stdout)
        stderr = text_or_empty(proc.stderr)
        if stdout:
            log.write("-- stdout --\n")
            log.write(stdout)
            if not stdout.endswith("\n"):
                log.write("\n")
        if stderr:
            log.write("-- stderr --\n")
            log.write(stderr)
            if not stderr.endswith("\n"):
                log.write("\n")
        log.write("\n")
    return proc


def assemble(args: argparse.Namespace, source: pathlib.Path, obj: pathlib.Path, log: pathlib.Path) -> bool:
    proc = run_cmd(log, f"assemble {source.name}", [str(args.assembler), "-object", str(source), str(obj)])
    return proc.returncode == 0


def link(args: argparse.Namespace, objects: list[pathlib.Path], out: pathlib.Path, log: pathlib.Path) -> bool:
    argv = [str(args.linker), "-binary", "-o", str(out)]
    argv.extend(str(path) for path in objects)
    proc = run_cmd(log, "link", argv)
    return proc.returncode == 0


def run_microemu(args: argparse.Namespace, bin_path: pathlib.Path, input_path: pathlib.Path, log: pathlib.Path) -> tuple[bool, int | None, str, str]:
    argv = [
        str(args.emulator),
        "--board", args.board,
        "--format", "bin",
        "--load-addr", "0",
        "--max-steps", str(args.max_steps),
        "--stop-on-self-branch",
        "--dump-regs",
        "--stats",
        "--uart-rx-file", str(input_path),
        str(bin_path),
    ]
    proc = run_cmd(log, "microemu", argv, binary=True)
    stdout = text_or_empty(proc.stdout)
    stderr = text_or_empty(proc.stderr)
    combined = stdout + stderr
    matches = REG_RE.findall(combined)
    actual = int(matches[-1], 16) if matches else None
    if "stopped on self-branch" not in combined:
        return False, actual, "emulator did not reach self-branch halt before max steps", stdout
    if proc.returncode != 0 or actual is None:
        return False, actual, "emulator halted without a parseable final V0", stdout
    return True, actual, "", stdout


def preview(text: str, limit: int = 600) -> str:
    text = text.replace("\r", "\\r").replace("\0", "\\0")
    if len(text) <= limit:
        return text
    return text[:limit] + f"... <truncated {len(text) - limit} chars>"


def format_v0(value: object) -> str:
    if value is None:
        return "unavailable"
    ivalue = int(value)
    return f"{ivalue} (0x{ivalue:04x})"


def classify_run(ok: bool, actual: int | None, reason: str) -> str:
    if actual == HEAP_OVERFLOW:
        return "hosted heap exhausted"
    if not ok:
        if "max steps" in reason:
            return "timeout or blocked hosted I/O"
        return reason
    return ""


def run_tool(
    args: argparse.Namespace,
    name: str,
    pcode_obj: pathlib.Path,
    interp_obj: pathlib.Path,
    hosted_obj: pathlib.Path,
    input_text: bytes,
    expected_substring: str,
) -> dict[str, object]:
    tool_dir = args.build_dir / name
    tool_dir.mkdir(parents=True, exist_ok=True)
    log = tool_dir / f"{name}.log"
    log.write_text("")
    input_path = tool_dir / f"{name}.stdin"
    bin_path = tool_dir / f"{name}.bin"
    input_path.write_bytes(input_text + b"\x04")

    result: dict[str, object] = {
        "name": name,
        "link_ok": False,
        "run_ok": False,
        "pass": False,
        "reason": "",
        "bin": bin_path,
        "bin_size": 0,
        "v0": None,
        "stdout": "",
        "stdin_bytes": len(input_text) + 1,
        "log": log,
    }
    if not pcode_obj.exists():
        result["reason"] = f"missing p-code object: {pcode_obj}"
        return result

    if not link(args, [interp_obj, hosted_obj, pcode_obj], bin_path, log):
        result["reason"] = "link failed"
        return result
    result["link_ok"] = True
    result["bin_size"] = bin_path.stat().st_size
    if int(result["bin_size"]) > 65536:
        result["reason"] = "linked image exceeds 64K"
        return result

    run_ok, actual, reason, stdout = run_microemu(args, bin_path, input_path, log)
    result["run_ok"] = run_ok
    result["v0"] = actual
    result["stdout"] = stdout
    result["reason"] = classify_run(run_ok, actual, reason)
    if run_ok and actual != HEAP_OVERFLOW and expected_substring in stdout:
        result["pass"] = True
    elif run_ok and not result["reason"]:
        result["reason"] = f"expected output substring not found: {expected_substring!r}"
    return result


def write_report(args: argparse.Namespace, hosted_obj: pathlib.Path, results: list[dict[str, object]]) -> None:
    report = args.build_dir / "report.txt"
    all_ok = all(result["pass"] for result in results)
    with report.open("w") as fp:
        fp.write("Self-host p-code execution smoke report\n")
        fp.write(f"Strict: {'yes' if args.strict else 'no'}\n")
        fp.write(f"Board: {args.board}\n")
        fp.write(f"Max steps: {args.max_steps}\n")
        fp.write(f"Hosted I/O object: {hosted_obj}\n")
        fp.write(f"Hosted I/O object size: {hosted_obj.stat().st_size if hosted_obj.exists() else 0}\n")
        fp.write("Hosted model: UART stdin/stdout/stderr; UART RX byte 0x04 is EOF; no filesystem.\n")
        fp.write(f"Hosted heap limit: 0x{HEAP_LIMIT:04x}\n")
        fp.write(f"Status: {'PASS' if all_ok else 'FAIL'}\n\n")
        for result in results:
            fp.write(f"{result['name']}:\n")
            fp.write(f"  link: {'PASS' if result['link_ok'] else 'FAIL'}\n")
            fp.write(f"  run: {'PASS' if result['run_ok'] else 'FAIL'}\n")
            fp.write(f"  smoke check: {'PASS' if result['pass'] else 'FAIL'}\n")
            fp.write(f"  final V0: {format_v0(result['v0'])}\n")
            fp.write(f"  linked binary size: {result['bin_size']}\n")
            if int(result["bin_size"]):
                fp.write(f"  approximate post-image heap room before MMIO: {max(0, HEAP_LIMIT - int(result['bin_size']))}\n")
            fp.write(f"  stdin bytes including EOF marker: {result['stdin_bytes']}\n")
            fp.write(f"  stdout bytes: {len(str(result['stdout']))}\n")
            if result["reason"]:
                fp.write(f"  reason: {result['reason']}\n")
            fp.write("  output preview:\n")
            for line in preview(str(result["stdout"])).splitlines()[:20]:
                fp.write(f"    {line}\n")
            fp.write(f"  log: {result['log']}\n\n")

        fp.write("Conclusion:\n")
        if all_ok:
            fp.write("- split p-code tools reached the tiny UART-backed execution smoke.\n")
        else:
            fp.write("- execution smoke is still report-only; see per-tool reason above.\n")
            fp.write("- V0=0xca10 means the minimal bump allocator ran out of 16-bit address space.\n")
            fp.write("- next steps are reducing runtime RAM footprint, moving tables out of fixed RAM, or defining a larger hosted memory model.\n")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assembler", required=True, type=pathlib.Path)
    parser.add_argument("--linker", required=True, type=pathlib.Path)
    parser.add_argument("--emulator", required=True, type=pathlib.Path)
    parser.add_argument("--board", default="hc1200-cpu")
    parser.add_argument("--max-steps", type=int, default=20000000)
    parser.add_argument("--runtime-dir", required=True, type=pathlib.Path)
    parser.add_argument("--link-build-dir", required=True, type=pathlib.Path)
    parser.add_argument("--build-dir", required=True, type=pathlib.Path)
    parser.add_argument("--strict", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    args.build_dir.mkdir(parents=True, exist_ok=True)
    hosted_log = args.build_dir / "hosted_io.log"
    hosted_log.write_text("")
    hosted_obj = args.build_dir / "hosted_io.o"
    interp_obj = args.link_build_dir / "pcode_interpreter.o"
    if not assemble(args, args.runtime_dir / "hosted_io.asm", hosted_obj, hosted_log):
        report = args.build_dir / "report.txt"
        report.write_text(f"Self-host p-code execution smoke report\nStatus: FAIL\nhosted_io assembly failed: {hosted_log}\n")
        print("selfhost-pcode-exec-smoke: FAIL")
        print(f"report: {report}")
        return 1 if args.strict else 0

    inputs = {
        "smallcpp": b"#define X 123\nint main() { return X; }\n",
        "smallcc": b"int main()\n{\nreturn 123;\n}\n",
    }
    expected = {
        "smallcpp": "return 123",
        "smallcc": "_main:",
    }
    results = []
    for name in ("smallcpp", "smallcc"):
        results.append(run_tool(
            args,
            name,
            args.link_build_dir / name / f"{name}.pcode.o",
            interp_obj,
            hosted_obj,
            inputs[name],
            expected[name],
        ))

    write_report(args, hosted_obj, results)
    all_ok = all(result["pass"] for result in results)
    print(f"selfhost-pcode-exec-smoke: {'PASS' if all_ok else 'FAIL'}")
    print(f"report: {args.build_dir / 'report.txt'}")
    if args.strict and not all_ok:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

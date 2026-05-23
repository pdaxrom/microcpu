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
SYMBOL_RE = re.compile(r"^([0-9a-fA-F]{4})\s+(\S+)\s*$")
HEAP_DIAG_RE = re.compile(
    r"HOSTED_HEAP error=([0-9a-fA-F]{4}) size=([0-9a-fA-F]{4}) "
    r"cur=([0-9a-fA-F]{4}) start=([0-9a-fA-F]{4}) "
    r"end=([0-9a-fA-F]{4}) service=([0-9a-fA-F]{4})"
)
HEAP_DIAG_COMPACT_RE = re.compile(
    r"\bHD\s+([0-9a-fA-F]{4})\s+([0-9a-fA-F]{4})\s+"
    r"([0-9a-fA-F]{4})\s+([0-9a-fA-F]{4})\s+"
    r"([0-9a-fA-F]{4})\s+([0-9a-fA-F]{4})"
)
HEAP_OVERFLOW = 0xCA10
HEAP_LIMIT = 0xFDE0
OBJECT_MAGIC = 0x5AA5


HOSTED_DIAG_ALIASES = [
    ("__hosted_last_error", "__hst_lasterr"),
    ("__hosted_last_alloc_size", "__hst_allocsz"),
    ("__hosted_heap_start", "__hst_hstart"),
    ("__hosted_heap_cur", "__hst_hcur"),
    ("__hosted_heap_end", "__hst_hend"),
    ("__hosted_fail_service", "__hst_service"),
    ("__hosted_fail_file_handle", "__hst_fhandle"),
]


ALLOC_HINTS = {
    "smallcpp": {
        10500: "smallcpp macro name table (macn)",
        7200: "smallcpp macro replacement pool (macq)",
        128: "smallcpp line buffer (pline or mline)",
        13000: "smallcpp compiler symbol table (symtab)",
    },
    "smallcc": {
        720: "smallcc switch table (swnext)",
        1600: "smallcc staging buffer (stage)",
        60: "smallcc while queue (wq)",
        8192: "smallcc literal pool (litq)",
        128: "smallcc line buffer (pline)",
        13000: "smallcc compiler symbol table (symtab)",
    },
}


SERVICE_NAMES = {
    1: "calloc",
}


def shell_join(argv: list[str]) -> str:
    return " ".join(shlex.quote(arg) for arg in argv)


def text_or_empty(value: bytes | str | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("latin-1", errors="replace")
    return value


def read_u16(data: bytes, offset: int) -> int:
    return data[offset] | (data[offset + 1] << 8)


def read_u32(data: bytes, offset: int) -> int:
    return read_u16(data, offset) | (read_u16(data, offset + 2) << 16)


def read_obj_name(raw: bytes) -> str:
    end = raw.find(b"\0")
    if end < 0:
        end = len(raw)
    return raw[:end].decode("ascii", errors="replace")


def parse_object(path: pathlib.Path) -> dict[str, object]:
    data = path.read_bytes()
    result: dict[str, object] = {
        "path": path,
        "code_len": path.stat().st_size if path.exists() else 0,
        "entries": {},
        "externs": [],
        "valid": False,
    }
    if len(data) < 0x20 or read_u16(data, 0) != OBJECT_MAGIC:
        return result
    ent_count = read_u16(data, 4)
    ext_count = read_u16(data, 6)
    code_len = read_u16(data, 8)
    pos = 0x20
    entries: dict[str, int] = {}
    externs: list[str] = []
    for _ in range(ent_count):
        if pos + 20 > len(data):
            return result
        name = read_obj_name(data[pos:pos + 16])
        value = read_u16(data, pos + 0x10)
        entries[name] = value
        pos += 20
    for _ in range(ext_count):
        if pos + 20 > len(data):
            return result
        externs.append(read_obj_name(data[pos:pos + 16]))
        pos += 20
    result["code_len"] = code_len
    result["entries"] = entries
    result["externs"] = externs
    result["valid"] = True
    return result


def parse_symbols(text: str) -> dict[str, int]:
    symbols: dict[str, int] = {}
    for line in text.splitlines():
        match = SYMBOL_RE.match(line.strip())
        if match:
            symbols[match.group(2)] = int(match.group(1), 16)
    return symbols


def strip_asm_comment(line: str) -> str:
    if ";" in line:
        return line.split(";", 1)[0]
    return line


def directive_item_count(text: str) -> int:
    text = text.strip()
    if not text:
        return 0
    count = 0
    quote = ""
    escaped = False
    item = ""
    for ch in text:
        if quote:
            item += ch
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == quote:
                quote = ""
            continue
        if ch == "'" or ch == '"':
            quote = ch
            item += ch
        elif ch == ",":
            if item.strip():
                count += 1
            item = ""
        else:
            item += ch
    if item.strip():
        count += 1
    return count


def parse_pcode_sections(asm_path: pathlib.Path, base: int) -> list[tuple[str, int, int]]:
    if not asm_path.exists():
        return []
    labels: dict[str, int] = {}
    offset = 0
    for raw in asm_path.read_text(errors="replace").splitlines():
        line = strip_asm_comment(raw).strip()
        if not line:
            continue
        if line.endswith(":"):
            labels[line[:-1]] = offset
            continue
        parts = line.split(None, 1)
        if not parts:
            continue
        op = parts[0].lower()
        args = parts[1] if len(parts) > 1 else ""
        if op == "db":
            offset += directive_item_count(args)
        elif op == "dw":
            offset += directive_item_count(args) * 2
        elif op == "ds":
            try:
                offset += int(args.split()[0], 0)
            except ValueError:
                pass
        elif op == "align":
            if offset & 1:
                offset += 1
    ranges: list[tuple[str, int, int]] = []
    for label, rel_start in labels.items():
        if not label.endswith("_code_start") and not label.endswith("_data_start"):
            continue
        end_label = label[:-5] + "end"
        rel_end = labels.get(end_label)
        if rel_end is None:
            continue
        kind = "p-code bytecode" if label.endswith("_code_start") else "p-code globals/data"
        ranges.append((kind, base + rel_start, base + rel_end))
    return ranges


def parse_heap_diag(stdout: str) -> dict[str, int]:
    matches = list(HEAP_DIAG_RE.finditer(stdout))
    if matches:
        match = matches[-1]
    else:
        compact = list(HEAP_DIAG_COMPACT_RE.finditer(stdout))
        if not compact:
            return {}
        match = compact[-1]
    keys = ["error", "alloc_size", "heap_cur", "heap_start", "heap_end", "service"]
    return {key: int(value, 16) for key, value in zip(keys, match.groups())}


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


def link(args: argparse.Namespace, objects: list[pathlib.Path], out: pathlib.Path, log: pathlib.Path) -> tuple[bool, dict[str, int], str]:
    argv = [str(args.linker), "-binary", "-symbols", "-o", str(out)]
    argv.extend(str(path) for path in objects)
    proc = run_cmd(log, "link", argv)
    symbols_text = text_or_empty(proc.stdout)
    return proc.returncode == 0, parse_symbols(symbols_text), symbols_text


def write_end_marker(path: pathlib.Path) -> None:
    path.write_text("public __pcd_gend\n__pcd_gend:\n")


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


def hex16(value: int | None) -> str:
    if value is None:
        return "n/a"
    return f"0x{value & 0xffff:04x}"


def classify_heap_root_cause(name: str, diag: dict[str, int]) -> str:
    if not diag:
        return "no hosted heap diagnostic was emitted"
    service = SERVICE_NAMES.get(diag.get("service", -1), f"service {diag.get('service', 0)}")
    alloc_size = diag.get("alloc_size", 0)
    hint = ALLOC_HINTS.get(name, {}).get(alloc_size)
    cur = diag.get("heap_cur", 0)
    end = diag.get("heap_end", HEAP_LIMIT)
    free = max(0, end - cur)
    if hint:
        return f"{service} failed while allocating {hint}; requested {alloc_size} bytes with {free} bytes below heap limit"
    return f"{service} failed while allocating {alloc_size} bytes with {free} bytes below heap limit"


def linked_object_ranges(objects: list[pathlib.Path]) -> list[dict[str, object]]:
    ranges: list[dict[str, object]] = []
    base = 0
    for path in objects:
        info = parse_object(path)
        code_len = int(info["code_len"])
        ranges.append({
            "path": path,
            "start": base,
            "end": base + code_len,
            "size": code_len,
            "entries": info["entries"],
            "externs": info["externs"],
            "valid": info["valid"],
        })
        base += code_len
    return ranges


def short_name(path: pathlib.Path) -> str:
    parts = path.parts
    if len(parts) >= 2:
        return "/".join(parts[-2:])
    return str(path)


def section_ranges_for_result(result: dict[str, object]) -> list[tuple[str, int, int]]:
    sections: list[tuple[str, int, int]] = []
    for obj in linked_object_ranges(list(result.get("objects", []))):
        path = obj["path"]
        if not isinstance(path, pathlib.Path) or not path.name.endswith(".pcode.o"):
            continue
        asm_path = path.with_suffix(".asm")
        sections.extend(parse_pcode_sections(asm_path, int(obj["start"])))
    return sections


def add_region(regions: list[tuple[str, int, int]], name: str, start: int | None, end: int | None) -> None:
    if start is None or end is None or end <= start:
        return
    regions.append((name, start, end))


def overlap_lines(regions: list[tuple[str, int, int]]) -> list[str]:
    lines: list[str] = []
    sorted_regions = sorted(regions, key=lambda item: item[1])
    for idx, left in enumerate(sorted_regions):
        for right in sorted_regions[idx + 1:]:
            if right[1] >= left[2]:
                break
            lines.append(
                f"{left[0]} {hex16(left[1])}-{hex16(left[2])} overlaps "
                f"{right[0]} {hex16(right[1])}-{hex16(right[2])}"
            )
    return lines


def top_symbol_sizes(symbols: dict[str, int], sections: list[tuple[str, int, int]], limit: int = 20) -> list[tuple[str, int, int]]:
    rows: list[tuple[str, int, int]] = []
    data_ranges = [(start, end) for kind, start, end in sections if kind == "p-code globals/data"]
    for start, end in data_ranges:
        scoped = sorted((addr, name) for name, addr in symbols.items() if start <= addr < end)
        for idx, (addr, name) in enumerate(scoped):
            next_addr = scoped[idx + 1][0] if idx + 1 < len(scoped) else end
            size = max(0, next_addr - addr)
            if size:
                rows.append((name, addr, size))
    rows.sort(key=lambda item: item[2], reverse=True)
    return rows[:limit]


def write_memory_map(args: argparse.Namespace, results: list[dict[str, object]]) -> None:
    path = args.build_dir / "memory-map.txt"
    with path.open("w") as fp:
        fp.write("Self-host p-code execution memory map\n")
        fp.write("Note: object symbols are limited to 15 characters; hosted diagnostics use short linker aliases.\n\n")
        for result in results:
            symbols = result.get("symbols", {})
            if not isinstance(symbols, dict):
                symbols = {}
            diag = result.get("heap_diag", {})
            if not isinstance(diag, dict):
                diag = {}
            fp.write(f"{result['name']}:\n")
            fp.write(f"  final linked binary size: {result['bin_size']}\n")
            fp.write(f"  hosted heap limit: {hex16(HEAP_LIMIT)}\n")
            fp.write("  hosted diagnostics:\n")
            for long_name, short_alias in HOSTED_DIAG_ALIASES:
                fp.write(f"    {long_name}: linker alias {short_alias}, address {hex16(symbols.get(short_alias))}\n")
            if diag:
                fp.write(f"    emitted error: {hex16(diag.get('error'))}\n")
                fp.write(f"    requested allocation: {diag.get('alloc_size', 0)} bytes\n")
                fp.write(f"    heap start: {hex16(diag.get('heap_start'))}\n")
                fp.write(f"    heap current at failure: {hex16(diag.get('heap_cur'))}\n")
                fp.write(f"    heap end: {hex16(diag.get('heap_end'))}\n")
                fp.write(f"    service: {SERVICE_NAMES.get(diag.get('service', -1), diag.get('service', 0))}\n")
                fp.write(f"    root cause: {classify_heap_root_cause(str(result['name']), diag)}\n")
            else:
                fp.write("    runtime values: unavailable; no HOSTED_HEAP line was emitted\n")

            fp.write("  linked object ranges:\n")
            object_ranges = linked_object_ranges(list(result.get("objects", [])))
            for obj in object_ranges:
                fp.write(
                    f"    {short_name(obj['path'])}: "
                    f"{hex16(int(obj['start']))}-{hex16(int(obj['end']))} "
                    f"({obj['size']} bytes)\n"
                )
            fp.write("  p-code sections:\n")
            sections = section_ranges_for_result(result)
            if sections:
                for name, start, end in sections:
                    fp.write(f"    {name}: {hex16(start)}-{hex16(end)} ({end - start} bytes)\n")
            else:
                fp.write("    none found\n")
            fp.write("  largest exported writable/global symbols:\n")
            top_symbols = top_symbol_sizes(symbols, sections)
            if top_symbols:
                for name, addr, size in top_symbols:
                    fp.write(f"    {name}: {hex16(addr)} ({size} bytes)\n")
            else:
                fp.write("    none found\n")

            fp.write("  VM/native stack regions:\n")
            stack_regions: list[tuple[str, int, int]] = []
            add_region(stack_regions, "VM operand stack", symbols.get("__pcd_vstk"), symbols.get("__pcd_vstkend"))
            add_region(stack_regions, "VM frame scratch", symbols.get("__pcd_frames"), symbols.get("__pcd_frame0"))
            add_region(stack_regions, "VM call frames", symbols.get("__pcd_frame0"), symbols.get("__pcd_frameend"))
            add_region(stack_regions, "native stack", symbols.get("__pcd_nstk"), symbols.get("__pcd_nstktop"))
            for name, start, end in stack_regions:
                fp.write(f"    {name}: {hex16(start)}-{hex16(end)} ({end - start} bytes)\n")
            nstktop = symbols.get("__pcd_nstktop")
            if nstktop is not None:
                fp.write(f"    native initial SP: {hex16(nstktop - 2)}\n")

            regions: list[tuple[str, int, int]] = []
            regions.extend(stack_regions)
            if diag:
                add_region(regions, "hosted heap used", diag.get("heap_start"), diag.get("heap_cur"))
                add_region(regions, "hosted heap free", diag.get("heap_cur"), diag.get("heap_end"))
                if diag.get("heap_start", 0) < int(result["bin_size"]):
                    regions.append(("linked image tail overlap guard", diag.get("heap_start", 0), int(result["bin_size"])))
            overlaps = overlap_lines(regions)
            fp.write("  overlap check:\n")
            if overlaps:
                for line in overlaps:
                    fp.write(f"    {line}\n")
            else:
                fp.write("    no overlaps detected among reported regions\n")
            fp.write("\n")


def run_tool(
    args: argparse.Namespace,
    name: str,
    pcode_objects: list[pathlib.Path],
    interp_obj: pathlib.Path,
    hosted_obj: pathlib.Path,
    end_marker_obj: pathlib.Path,
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
        "objects": [],
        "symbols": {},
        "link_symbols_text": "",
        "heap_diag": {},
    }
    missing = [path for path in pcode_objects if not path.exists()]
    if missing:
        result["reason"] = "missing p-code object: " + ", ".join(str(path) for path in missing)
        return result

    objects = [interp_obj, hosted_obj] + pcode_objects + [end_marker_obj]
    result["objects"] = objects
    link_ok, symbols, symbols_text = link(args, objects, bin_path, log)
    result["symbols"] = symbols
    result["link_symbols_text"] = symbols_text
    if not link_ok:
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
    result["heap_diag"] = parse_heap_diag(stdout)
    result["reason"] = classify_run(run_ok, actual, reason)
    if run_ok and actual != HEAP_OVERFLOW and expected_substring in stdout:
        result["pass"] = True
    elif run_ok and not result["reason"]:
        result["reason"] = f"expected output substring not found: {expected_substring!r}"
    return result


def write_report(args: argparse.Namespace, hosted_obj: pathlib.Path, results: list[dict[str, object]]) -> None:
    write_memory_map(args, results)
    report = args.build_dir / "report.txt"
    memory_map = args.build_dir / "memory-map.txt"
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
        fp.write(f"Memory map: {memory_map}\n")
        fp.write(f"Status: {'PASS' if all_ok else 'FAIL'}\n\n")
        for result in results:
            heap_diag = result.get("heap_diag", {})
            if not isinstance(heap_diag, dict):
                heap_diag = {}
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
            if heap_diag:
                fp.write("  hosted heap diagnostic:\n")
                fp.write(f"    error: {hex16(heap_diag.get('error'))}\n")
                fp.write(f"    requested allocation: {heap_diag.get('alloc_size', 0)} bytes\n")
                fp.write(f"    heap start: {hex16(heap_diag.get('heap_start'))}\n")
                fp.write(f"    heap current: {hex16(heap_diag.get('heap_cur'))}\n")
                fp.write(f"    heap end: {hex16(heap_diag.get('heap_end'))}\n")
                fp.write(f"    service: {SERVICE_NAMES.get(heap_diag.get('service', -1), heap_diag.get('service', 0))}\n")
                fp.write(f"    root cause: {classify_heap_root_cause(str(result['name']), heap_diag)}\n")
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
    end_marker_asm = args.build_dir / "pcode_end_marker.asm"
    end_marker_obj = args.build_dir / "pcode_end_marker.o"
    if not assemble(args, args.runtime_dir / "hosted_io.asm", hosted_obj, hosted_log):
        report = args.build_dir / "report.txt"
        report.write_text(f"Self-host p-code execution smoke report\nStatus: FAIL\nhosted_io assembly failed: {hosted_log}\n")
        print("selfhost-pcode-exec-smoke: FAIL")
        print(f"report: {report}")
        return 1 if args.strict else 0
    write_end_marker(end_marker_asm)
    if not assemble(args, end_marker_asm, end_marker_obj, hosted_log):
        report = args.build_dir / "report.txt"
        report.write_text(f"Self-host p-code execution smoke report\nStatus: FAIL\np-code end marker assembly failed: {hosted_log}\n")
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
            sorted((args.link_build_dir / name).glob("*.pcode.o")),
            interp_obj,
            hosted_obj,
            end_marker_obj,
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

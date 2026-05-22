#!/usr/bin/env python3
"""Conservative textual p-code compaction and diagnostics."""

from __future__ import annotations

import pathlib
import re
from collections import Counter, defaultdict
from dataclasses import dataclass

import run_pcode_microemu as pcode


CODE_LABEL_OPS = {"func", "static_func", "label"}
NON_CODE_OPS = {"entry", "data_label", "static_data_label", "data8", "data16", "zero", "end"}
BRANCH_OPS = {"jmp", "jz", "jnz"}
TEMP_OFFSETS = {"0", "2"}
LITERAL_LABEL_RE = re.compile(r"^(?:__p[0-9]+_)?L[0-9]+$")


@dataclass
class PcaLine:
    op: str
    args: list[str]


def read_pca_lines(path: pathlib.Path) -> list[PcaLine]:
    lines: list[PcaLine] = []
    for raw in path.read_text().splitlines():
        line = pcode.clean_line(raw)
        if not line:
            continue
        parts = line.split()
        lines.append(PcaLine(parts[0], parts[1:]))
    return lines


def write_pca_lines(path: pathlib.Path, lines: list[PcaLine]) -> None:
    path.write_text("\n".join(" ".join([line.op] + line.args) for line in lines) + "\n")


def build_code_maps(lines: list[PcaLine]) -> tuple[
    list[PcaLine],
    dict[int, int],
    list[int],
    dict[int, list[str]],
    list[tuple[str, int]],
]:
    code: list[PcaLine] = []
    line_to_code: dict[int, int] = {}
    code_to_line: list[int] = []
    labels: dict[int, list[str]] = defaultdict(list)
    functions: list[tuple[str, int]] = []
    current_function = ""
    code_index = 0
    for line_index, line in enumerate(lines):
        if line.op in ("func", "static_func"):
            current_function = line.args[0]
            labels[code_index].append(current_function)
            functions.append((current_function, code_index))
        elif line.op == "label":
            labels[code_index].append(line.args[0])
        elif line.op in NON_CODE_OPS:
            pass
        else:
            line_to_code[line_index] = code_index
            code_to_line.append(line_index)
            code.append(line)
            code_index += 1
    return code, line_to_code, code_to_line, labels, functions


def function_ranges(functions: list[tuple[str, int]], code_count: int) -> list[tuple[int, int]]:
    ranges: list[tuple[int, int]] = []
    for index, item in enumerate(functions):
        start = item[1]
        end = functions[index + 1][1] if index + 1 < len(functions) else code_count
        ranges.append((start, end))
    if not ranges:
        ranges.append((0, code_count))
    return ranges


def compute_temp_liveness(
    code: list[PcaLine],
    labels: dict[int, list[str]],
    functions: list[tuple[str, int]],
    temp: str,
) -> tuple[list[bool], list[bool]]:
    live_before = [False] * len(code)
    live_after = [False] * len(code)
    label_to_index = {label: index for index, names in labels.items() for label in names}

    for start, end in function_ranges(functions, len(code)):
        changed = True
        while changed:
            changed = False
            index = end - 1
            while index >= start:
                line = code[index]
                successors: list[int] = []
                if line.op == "ret":
                    successors = []
                elif line.op == "jmp":
                    target = label_to_index.get(line.args[0], end)
                    if start <= target < end:
                        successors = [target]
                elif line.op in ("jz", "jnz"):
                    if index + 1 < end:
                        successors.append(index + 1)
                    target = label_to_index.get(line.args[0], end)
                    if start <= target < end:
                        successors.append(target)
                else:
                    if index + 1 < end:
                        successors = [index + 1]

                new_after = any(live_before[succ] for succ in successors)
                reads = line.op == "llocal" and line.args == [temp]
                writes = line.op == "slocal" and line.args == [temp]
                new_before = reads or (new_after and not writes)
                if new_after != live_after[index] or new_before != live_before[index]:
                    live_after[index] = new_after
                    live_before[index] = new_before
                    changed = True
                index -= 1
    return live_before, live_after


def removable_temp_roundtrips(lines: list[PcaLine]) -> set[int]:
    code, _line_to_code, code_to_line, labels, functions = build_code_maps(lines)
    remove_lines: set[int] = set()
    for temp in TEMP_OFFSETS:
        _live_before, live_after = compute_temp_liveness(code, labels, functions, temp)
        for index in range(0, len(code) - 1):
            first = code[index]
            second = code[index + 1]
            if first.op != "slocal" or first.args != [temp]:
                continue
            if second.op != "llocal" or second.args != [temp]:
                continue
            if labels.get(index) or labels.get(index + 1):
                continue
            if live_after[index + 1]:
                continue
            remove_lines.add(code_to_line[index])
            remove_lines.add(code_to_line[index + 1])
    return remove_lines


def optimize_lines(lines: list[PcaLine]) -> tuple[list[PcaLine], dict[str, int]]:
    total_removed = 0
    passes = 0
    current = list(lines)
    while True:
        remove_lines = removable_temp_roundtrips(current)
        if not remove_lines:
            break
        current = [line for index, line in enumerate(current) if index not in remove_lines]
        total_removed += len(remove_lines) // 2
        passes += 1
        if passes > 16:
            break
    return current, {
        "passes": passes,
        "removed_temp_roundtrips": total_removed,
    }


def optimize_pca_file(input_path: pathlib.Path, output_path: pathlib.Path) -> dict[str, int]:
    before = analyze_pca(input_path)
    lines = read_pca_lines(input_path)
    optimized, opt_stats = optimize_lines(lines)
    write_pca_lines(output_path, optimized)
    after = analyze_pca(output_path)
    return {
        "passes": opt_stats["passes"],
        "removed_temp_roundtrips": opt_stats["removed_temp_roundtrips"],
        "bytecode_before": int(before["bytecode_bytes"]),
        "bytecode_after": int(after["bytecode_bytes"]),
        "bytecode_saved": int(before["bytecode_bytes"]) - int(after["bytecode_bytes"]),
    }


def literal_bytes(data: list[int], data_labels: dict[str, int]) -> int:
    offsets = sorted(set(data_labels.values()) | {len(data)})
    total = 0
    for label, offset in data_labels.items():
        if not LITERAL_LABEL_RE.match(label):
            continue
        next_offset = len(data)
        for candidate in offsets:
            if candidate > offset:
                next_offset = candidate
                break
        total += max(0, next_offset - offset)
    return total


def analyze_pca(path: pathlib.Path) -> dict[str, object]:
    entry, insns, _labels, data_labels, data = pcode.parse_pca(path)
    bytecode_bytes = sum(insn.size for insn in insns)
    histogram: Counter[str] = Counter(insn.op for insn in insns)
    opcode_bytes: Counter[str] = Counter()
    pairs: Counter[str] = Counter()
    for index, insn in enumerate(insns):
        opcode_bytes[insn.op] += insn.size
        if index + 1 < len(insns):
            pairs[f"{insn.op} {insns[index + 1].op}"] += 1

    branch_short = 0
    branch_long = 0
    for insn in insns:
        if insn.op in BRANCH_OPS:
            if insn.size == 2:
                branch_short += 1
            else:
                branch_long += 1

    iconst_short = 0
    iconst_s8 = 0
    iconst_u16 = 0
    llocal_short = 0
    llocal_s8 = 0
    llocal_u16 = 0
    slocal_short = 0
    slocal_s8 = 0
    slocal_u16 = 0
    temp_roundtrips = 0
    for index, insn in enumerate(insns):
        if insn.op == "iconst":
            value = pcode.parse_int(insn.args[0])
            if value in (-1, 0, 1, 2):
                iconst_short += 1
            elif -128 <= value <= 127:
                iconst_s8 += 1
            else:
                iconst_u16 += 1
        elif insn.op in ("llocal", "slocal"):
            value = pcode.parse_int(insn.args[0])
            if 0 <= value <= 3:
                if insn.op == "llocal":
                    llocal_short += 1
                else:
                    slocal_short += 1
            elif -128 <= value <= 127:
                if insn.op == "llocal":
                    llocal_s8 += 1
                else:
                    slocal_s8 += 1
            else:
                if insn.op == "llocal":
                    llocal_u16 += 1
                else:
                    slocal_u16 += 1
        if index + 1 < len(insns):
            next_insn = insns[index + 1]
            if insn.op == "slocal" and next_insn.op == "llocal" and insn.args == next_insn.args:
                temp_roundtrips += 1

    call_count = histogram["call"]
    icall_count = histogram["icall"]
    ncall_count = histogram["ncall"]
    natives = {insn.args[0] for insn in insns if insn.op == "ncall"}

    code, _line_to_code, _code_to_line, _labels_by_code, _functions = build_code_maps(read_pca_lines(path))
    function_sizes: Counter[str] = Counter()
    current_function = "(prelude)"
    code_index = 0
    for line in read_pca_lines(path):
        if line.op in ("func", "static_func"):
            current_function = line.args[0]
        elif line.op in NON_CODE_OPS or line.op in CODE_LABEL_OPS:
            pass
        else:
            if code_index < len(code):
                function_sizes[current_function] += insns[code_index].size
                code_index += 1

    return {
        "entry": entry,
        "bytecode_bytes": bytecode_bytes,
        "global_data_bytes": len(data),
        "string_literal_bytes": literal_bytes(data, data_labels),
        "native_table_bytes": len(natives) * 2,
        "metadata_bytes": 4,
        "payload_bytes": bytecode_bytes + len(data) + len(natives) * 2,
        "function_count": sum(1 for line in read_pca_lines(path) if line.op in ("func", "static_func")),
        "global_count": len([name for name in data_labels if not LITERAL_LABEL_RE.match(name)]),
        "opcode_histogram": histogram,
        "opcode_bytes": opcode_bytes,
        "opcode_pairs": pairs,
        "top_functions": function_sizes.most_common(20),
        "temp_roundtrips": temp_roundtrips,
        "call_count": call_count,
        "icall_count": icall_count,
        "ncall_count": ncall_count,
        "branch_short": branch_short,
        "branch_long": branch_long,
        "iconst_short": iconst_short,
        "iconst_s8": iconst_s8,
        "iconst_u16": iconst_u16,
        "llocal_short": llocal_short,
        "llocal_s8": llocal_s8,
        "llocal_u16": llocal_u16,
        "slocal_short": slocal_short,
        "slocal_s8": slocal_s8,
        "slocal_u16": slocal_u16,
    }


def format_analysis(stats: dict[str, object], indent: str = "  ") -> list[str]:
    lines: list[str] = []
    lines.append(f"{indent}total p-code payload: {stats['payload_bytes']}")
    lines.append(f"{indent}bytecode bytes: {stats['bytecode_bytes']}")
    lines.append(f"{indent}global data bytes: {stats['global_data_bytes']}")
    lines.append(f"{indent}string literal bytes: {stats['string_literal_bytes']}")
    lines.append(f"{indent}native table bytes: {stats['native_table_bytes']}")
    lines.append(f"{indent}metadata bytes: {stats['metadata_bytes']}")
    lines.append(f"{indent}functions: {stats['function_count']}")
    lines.append(f"{indent}globals: {stats['global_count']}")
    lines.append(f"{indent}calls: CALL={stats['call_count']} ICALL={stats['icall_count']} NCALL={stats['ncall_count']}")
    lines.append(f"{indent}branches: short={stats['branch_short']} long={stats['branch_long']}")
    lines.append(
        f"{indent}constants: short={stats['iconst_short']} s8={stats['iconst_s8']} u16={stats['iconst_u16']}"
    )
    lines.append(
        f"{indent}locals: lshort={stats['llocal_short']} ls8={stats['llocal_s8']} lu16={stats['llocal_u16']} "
        f"sshort={stats['slocal_short']} ss8={stats['slocal_s8']} su16={stats['slocal_u16']}"
    )
    lines.append(f"{indent}temp store/load roundtrips: {stats['temp_roundtrips']}")
    lines.append(f"{indent}largest functions:")
    for name, size in stats["top_functions"]:
        lines.append(f"{indent}  {name}: {size}")
    lines.append(f"{indent}opcode histogram:")
    for name, count in stats["opcode_histogram"].most_common(20):
        lines.append(f"{indent}  {name}: {count}")
    lines.append(f"{indent}opcode byte totals:")
    for name, count in stats["opcode_bytes"].most_common(20):
        lines.append(f"{indent}  {name}: {count}")
    lines.append(f"{indent}common opcode pairs:")
    for name, count in stats["opcode_pairs"].most_common(20):
        lines.append(f"{indent}  {name}: {count}")
    return lines

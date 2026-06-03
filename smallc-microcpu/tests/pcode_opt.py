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
    remove_lines, _counts = removable_temp_roundtrip_details(lines)
    return remove_lines


def removable_temp_roundtrip_details(lines: list[PcaLine]) -> tuple[set[int], Counter[str]]:
    code, _line_to_code, code_to_line, labels, functions = build_code_maps(lines)
    remove_lines: set[int] = set()
    counts: Counter[str] = Counter()
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
            counts[temp] += 1
    return remove_lines, counts


def local_access_size(temp: str) -> int:
    value = pcode.parse_int(temp)
    if 0 <= value <= 3:
        return 1
    if -128 <= value <= 127:
        return 2
    return 3


def compute_code_layout(lines: list[PcaLine]) -> tuple[
    list[PcaLine],
    list[int],
    dict[int, list[str]],
    dict[str, int],
    dict[str, int],
    list[int],
    list[int],
]:
    code, _line_to_code, code_to_line, labels, _functions = build_code_maps(lines)
    label_to_index = {label: index for index, names in labels.items() for label in names}
    insns = [pcode.Insn(line.op, line.args) for line in code]
    for insn in insns:
        insn.size = 2 if insn.op in BRANCH_OPS else pcode.insn_size(insn, label_to_index)
    for _iteration in range(8):
        pc = 0
        for insn in insns:
            insn.addr = pc
            pc += insn.size
        label_addr = {
            name: insns[index].addr if index < len(insns) else pc
            for name, index in label_to_index.items()
        }
        changed = False
        for insn in insns:
            if insn.op not in BRANCH_OPS:
                continue
            target = label_addr[insn.args[0]]
            rel = target - (insn.addr + 2)
            new_size = 2 if -128 <= rel <= 127 else 3
            if new_size != insn.size:
                insn.size = new_size
                changed = True
        if not changed:
            break
    pc = 0
    addrs: list[int] = []
    sizes: list[int] = []
    for insn in insns:
        addrs.append(pc)
        sizes.append(insn.size)
        pc += insn.size
    label_addr = {
        name: addrs[index] if index < len(addrs) else pc
        for name, index in label_to_index.items()
    }
    return code, code_to_line, labels, label_to_index, label_addr, addrs, sizes


def branch_size_from_addr(op: str, addr: int, target_addr: int) -> int:
    if op not in BRANCH_OPS:
        return 0
    rel = target_addr - (addr + 2)
    return 2 if -128 <= rel <= 127 else 3


def threaded_branch_target(
    label: str,
    code: list[PcaLine],
    label_to_index: dict[str, int],
) -> str:
    seen: set[str] = set()
    current = label
    while current not in seen:
        seen.add(current)
        index = label_to_index.get(current)
        if index is None or index >= len(code):
            break
        line = code[index]
        if line.op != "jmp":
            break
        next_label = line.args[0]
        if next_label == current:
            break
        current = next_label
    return current


def rewrite_branches(lines: list[PcaLine]) -> tuple[list[PcaLine], dict[str, int]]:
    code, code_to_line, labels, label_to_index, label_addr, addrs, sizes = compute_code_layout(lines)
    replacements: dict[int, PcaLine] = {}
    removals: set[int] = set()
    touched: set[int] = set()
    stats = {
        "const_branch_to_jump": 0,
        "const_branch_removed": 0,
        "jump_to_next_removed": 0,
        "cond_to_next_replaced": 0,
        "inverted_branch_jumps": 0,
        "branch_threaded": 0,
        "branch_thread_byte_savings": 0,
    }

    for index in range(0, len(code) - 1):
        first = code[index]
        second = code[index + 1]
        if first.op != "iconst" or second.op not in ("jz", "jnz"):
            continue
        if labels.get(index + 1):
            continue
        value = pcode.parse_int(first.args[0])
        always_taken = (second.op == "jz" and value == 0) or (second.op == "jnz" and value != 0)
        always_not_taken = (second.op == "jz" and value != 0) or (second.op == "jnz" and value == 0)
        if always_taken:
            replacements[code_to_line[index]] = PcaLine("jmp", [second.args[0]])
            removals.add(code_to_line[index + 1])
            touched.add(index)
            touched.add(index + 1)
            stats["const_branch_to_jump"] += 1
        elif always_not_taken:
            removals.add(code_to_line[index])
            removals.add(code_to_line[index + 1])
            touched.add(index)
            touched.add(index + 1)
            stats["const_branch_removed"] += 1

    for index in range(0, len(code) - 1):
        first = code[index]
        second = code[index + 1]
        if index in touched or index + 1 in touched:
            continue
        if first.op not in ("jz", "jnz") or second.op != "jmp":
            continue
        if labels.get(index + 1):
            continue
        target_index = label_to_index.get(first.args[0])
        if target_index != index + 2:
            continue
        new_op = "jnz" if first.op == "jz" else "jz"
        replacements[code_to_line[index]] = PcaLine(new_op, [second.args[0]])
        removals.add(code_to_line[index + 1])
        touched.add(index)
        touched.add(index + 1)
        stats["inverted_branch_jumps"] += 1

    for index, line in enumerate(code):
        if index in touched or line.op not in BRANCH_OPS:
            continue
        target_index = label_to_index.get(line.args[0])
        if target_index is None:
            continue
        if target_index == index + 1:
            if line.op == "jmp":
                removals.add(code_to_line[index])
                touched.add(index)
                stats["jump_to_next_removed"] += 1
            else:
                replacements[code_to_line[index]] = PcaLine("drop", [])
                touched.add(index)
                stats["cond_to_next_replaced"] += 1
            continue

        next_label = threaded_branch_target(line.args[0], code, label_to_index)
        if next_label == line.args[0] or next_label not in label_addr:
            continue
        new_size = branch_size_from_addr(line.op, addrs[index], label_addr[next_label])
        if new_size > sizes[index]:
            continue
        replacements[code_to_line[index]] = PcaLine(line.op, [next_label])
        touched.add(index)
        stats["branch_threaded"] += 1
        stats["branch_thread_byte_savings"] += sizes[index] - new_size

    if not replacements and not removals:
        return list(lines), stats
    return [
        replacements.get(index, line)
        for index, line in enumerate(lines)
        if index not in removals
    ], stats


def rewrite_store_load_roundtrips(lines: list[PcaLine]) -> tuple[list[PcaLine], Counter[str], int]:
    code, _line_to_code, code_to_line, labels, _functions = build_code_maps(lines)
    rewrites: dict[int, PcaLine] = {}
    counts: Counter[str] = Counter()
    saved = 0
    for index in range(0, len(code) - 1):
        first = code[index]
        second = code[index + 1]
        if first.op != "slocal" or second.op != "llocal" or first.args != second.args:
            continue
        if labels.get(index + 1):
            continue
        temp = first.args[0]
        lload_size = local_access_size(temp)
        if lload_size <= 1:
            continue
        rewrites[code_to_line[index]] = PcaLine("dup", [])
        rewrites[code_to_line[index + 1]] = PcaLine("slocal", [temp])
        counts[temp] += 1
        saved += lload_size - 1
    if not rewrites:
        return list(lines), counts, 0
    return [rewrites.get(index, line) for index, line in enumerate(lines)], counts, saved


def rewrite_immediate_s8(lines: list[PcaLine]) -> tuple[list[PcaLine], dict[str, int]]:
    code, _line_to_code, code_to_line, labels, _functions = build_code_maps(lines)
    replacements: dict[int, PcaLine] = {}
    removals: set[int] = set()
    op_map = {
        "add": "addi",
        "sub": "subi",
        "eq": "eqi",
    }
    counts = {
        "addi_s8_rewrites": 0,
        "addi_u16_rewrites": 0,
        "subi_s8_rewrites": 0,
        "eqi_s8_rewrites": 0,
        "slocal_const_s8_rewrites": 0,
    }
    for index in range(0, len(code) - 1):
        first = code[index]
        second = code[index + 1]
        if first.op != "iconst" or (second.op not in op_map and second.op != "slocal"):
            continue
        if labels.get(index + 1):
            continue
        value = pcode.parse_int(first.args[0])
        if second.op == "slocal":
            if second.args[0] == "0" and -128 <= value <= 127 and value not in (-1, 0, 1, 2):
                replacements[code_to_line[index]] = PcaLine("slocal0_s8", [first.args[0]])
                removals.add(code_to_line[index + 1])
                counts["slocal_const_s8_rewrites"] += 1
            elif second.args[0] == "2" and -128 <= value <= 127 and value not in (-1, 0, 1, 2):
                replacements[code_to_line[index]] = PcaLine("slocal2_s8", [first.args[0]])
                removals.add(code_to_line[index + 1])
                counts["slocal_const_s8_rewrites"] += 1
            continue
        if second.op == "add" and not -128 <= value <= 127:
            replacements[code_to_line[index]] = PcaLine("addi_u16", [first.args[0]])
            removals.add(code_to_line[index + 1])
            counts["addi_u16_rewrites"] += 1
            continue
        if not -128 <= value <= 127:
            continue
        new_op = op_map[second.op]
        replacements[code_to_line[index]] = PcaLine(new_op, [first.args[0]])
        removals.add(code_to_line[index + 1])
        counts[new_op + "_s8_rewrites"] += 1
    if not replacements:
        return list(lines), counts
    return [
        replacements.get(index, line)
        for index, line in enumerate(lines)
        if index not in removals
    ], counts


def rewrite_zero_local_stores(lines: list[PcaLine]) -> tuple[list[PcaLine], int]:
    code, _line_to_code, code_to_line, labels, _functions = build_code_maps(lines)
    replacements: dict[int, PcaLine] = {}
    removals: set[int] = set()
    count = 0
    for index in range(0, len(code) - 1):
        first = code[index]
        second = code[index + 1]
        if first.op != "iconst" or second.op != "slocal":
            continue
        if labels.get(index + 1):
            continue
        value = pcode.parse_int(first.args[0])
        if value != 0:
            continue
        replacements[code_to_line[index]] = PcaLine("zlocal", [second.args[0]])
        removals.add(code_to_line[index + 1])
        count += 1
    if not replacements:
        return list(lines), 0
    return [
        replacements.get(index, line)
        for index, line in enumerate(lines)
        if index not in removals
    ], count


def rewrite_ladd_local0_2(lines: list[PcaLine]) -> tuple[list[PcaLine], int]:
    code, _line_to_code, code_to_line, labels, _functions = build_code_maps(lines)
    replacements: dict[int, PcaLine] = {}
    removals: set[int] = set()
    count = 0
    for index in range(0, len(code) - 2):
        first = code[index]
        second = code[index + 1]
        third = code[index + 2]
        if first.op != "llocal" or first.args != ["0"]:
            continue
        if second.op != "llocal" or second.args != ["2"]:
            continue
        if third.op != "add":
            continue
        if labels.get(index + 1) or labels.get(index + 2):
            continue
        replacements[code_to_line[index]] = PcaLine("ladd_local0_2", [])
        removals.add(code_to_line[index + 1])
        removals.add(code_to_line[index + 2])
        count += 1
    if not replacements:
        return list(lines), 0
    return [
        replacements.get(index, line)
        for index, line in enumerate(lines)
        if index not in removals
    ], count


def optimize_lines(lines: list[PcaLine]) -> tuple[list[PcaLine], dict[str, int]]:
    total_removed = 0
    total_rewritten = 0
    total_rewrite_saved = 0
    total_const_to_jump = 0
    total_const_removed = 0
    total_jump_next_removed = 0
    total_cond_next_replaced = 0
    total_inverted_branch_jumps = 0
    total_branch_threaded = 0
    total_branch_thread_saved = 0
    total_addi_rewrites = 0
    total_addi_u16_rewrites = 0
    total_subi_rewrites = 0
    total_eqi_rewrites = 0
    total_slocal_const_rewrites = 0
    total_zlocal_rewrites = 0
    total_ladd_local0_2_rewrites = 0
    passes = 0
    current = list(lines)
    while True:
        remove_lines = removable_temp_roundtrips(current)
        removed = len(remove_lines) // 2
        if remove_lines:
            current = [line for index, line in enumerate(current) if index not in remove_lines]
        current, rewrite_counts, rewrite_saved = rewrite_store_load_roundtrips(current)
        rewritten = sum(rewrite_counts.values())
        current, imm_rewrites = rewrite_immediate_s8(current)
        addi_rewrites = imm_rewrites["addi_s8_rewrites"]
        addi_u16_rewrites = imm_rewrites["addi_u16_rewrites"]
        subi_rewrites = imm_rewrites["subi_s8_rewrites"]
        eqi_rewrites = imm_rewrites["eqi_s8_rewrites"]
        slocal_const_rewrites = imm_rewrites["slocal_const_s8_rewrites"]
        current, zlocal_rewrites = rewrite_zero_local_stores(current)
        current, ladd_local0_2_rewrites = rewrite_ladd_local0_2(current)
        current, branch_stats = rewrite_branches(current)
        branch_changes = (
            branch_stats["const_branch_to_jump"]
            + branch_stats["const_branch_removed"]
            + branch_stats["jump_to_next_removed"]
            + branch_stats["cond_to_next_replaced"]
            + branch_stats["inverted_branch_jumps"]
            + branch_stats["branch_threaded"]
        )
        if not removed and not rewritten and not addi_rewrites and not addi_u16_rewrites and not subi_rewrites and not eqi_rewrites and not slocal_const_rewrites and not zlocal_rewrites and not ladd_local0_2_rewrites and not branch_changes:
            break
        total_removed += removed
        total_rewritten += rewritten
        total_rewrite_saved += rewrite_saved
        total_addi_rewrites += addi_rewrites
        total_addi_u16_rewrites += addi_u16_rewrites
        total_subi_rewrites += subi_rewrites
        total_eqi_rewrites += eqi_rewrites
        total_slocal_const_rewrites += slocal_const_rewrites
        total_zlocal_rewrites += zlocal_rewrites
        total_ladd_local0_2_rewrites += ladd_local0_2_rewrites
        total_const_to_jump += branch_stats["const_branch_to_jump"]
        total_const_removed += branch_stats["const_branch_removed"]
        total_jump_next_removed += branch_stats["jump_to_next_removed"]
        total_cond_next_replaced += branch_stats["cond_to_next_replaced"]
        total_inverted_branch_jumps += branch_stats["inverted_branch_jumps"]
        total_branch_threaded += branch_stats["branch_threaded"]
        total_branch_thread_saved += branch_stats["branch_thread_byte_savings"]
        passes += 1
        if passes > 16:
            break
    return current, {
        "passes": passes,
        "removed_temp_roundtrips": total_removed,
        "rewritten_store_load_roundtrips": total_rewritten,
        "rewrite_byte_savings": total_rewrite_saved,
        "addi_s8_rewrites": total_addi_rewrites,
        "addi_u16_rewrites": total_addi_u16_rewrites,
        "subi_s8_rewrites": total_subi_rewrites,
        "eqi_s8_rewrites": total_eqi_rewrites,
        "slocal_const_s8_rewrites": total_slocal_const_rewrites,
        "zlocal_rewrites": total_zlocal_rewrites,
        "ladd_local0_2_rewrites": total_ladd_local0_2_rewrites,
        "const_branch_to_jump": total_const_to_jump,
        "const_branch_removed": total_const_removed,
        "jump_to_next_removed": total_jump_next_removed,
        "cond_to_next_replaced": total_cond_next_replaced,
        "inverted_branch_jumps": total_inverted_branch_jumps,
        "branch_threaded": total_branch_threaded,
        "branch_thread_byte_savings": total_branch_thread_saved,
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
        "rewritten_store_load_roundtrips": opt_stats["rewritten_store_load_roundtrips"],
        "rewrite_byte_savings": opt_stats["rewrite_byte_savings"],
        "addi_s8_rewrites": opt_stats["addi_s8_rewrites"],
        "addi_u16_rewrites": opt_stats["addi_u16_rewrites"],
        "subi_s8_rewrites": opt_stats["subi_s8_rewrites"],
        "eqi_s8_rewrites": opt_stats["eqi_s8_rewrites"],
        "slocal_const_s8_rewrites": opt_stats["slocal_const_s8_rewrites"],
        "zlocal_rewrites": opt_stats["zlocal_rewrites"],
        "ladd_local0_2_rewrites": opt_stats["ladd_local0_2_rewrites"],
        "const_branch_to_jump": opt_stats["const_branch_to_jump"],
        "const_branch_removed": opt_stats["const_branch_removed"],
        "jump_to_next_removed": opt_stats["jump_to_next_removed"],
        "cond_to_next_replaced": opt_stats["cond_to_next_replaced"],
        "inverted_branch_jumps": opt_stats["inverted_branch_jumps"],
        "branch_threaded": opt_stats["branch_threaded"],
        "branch_thread_byte_savings": opt_stats["branch_thread_byte_savings"],
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


def pca_line_size(line: PcaLine, insn: pcode.Insn) -> int:
    if line.op == "iconst":
        value = pcode.parse_int(line.args[0])
        if value in (-1, 0, 1, 2):
            return 1
        if -128 <= value <= 127:
            return 2
        return 3
    return insn.size


def analyze_peephole_candidates(
    lines: list[PcaLine],
    insns: list[pcode.Insn],
) -> dict[str, object]:
    code, _line_to_code, _code_to_line, labels, _functions = build_code_maps(lines)
    label_to_index = {label: index for index, names in labels.items() for label in names}
    temp_loads: Counter[str] = Counter()
    temp_stores: Counter[str] = Counter()
    store_load_pairs: Counter[str] = Counter()
    load_store_pairs: Counter[str] = Counter()
    const_branch_to_jump = 0
    const_branch_remove = 0
    jump_to_next = 0
    branch_to_branch = 0
    estimated_savings = 0
    _remove_lines, removable_by_temp = removable_temp_roundtrip_details(lines)

    for line in code:
        if line.op == "llocal":
            temp_loads[line.args[0]] += 1
        elif line.op == "slocal":
            temp_stores[line.args[0]] += 1

    for index in range(0, len(code) - 1):
        first = code[index]
        second = code[index + 1]
        if first.op == "slocal" and second.op == "llocal" and first.args == second.args:
            store_load_pairs[first.args[0]] += 1
        if first.op == "llocal" and second.op == "slocal" and first.args == second.args:
            load_store_pairs[first.args[0]] += 1

        if first.op == "iconst" and second.op in ("jz", "jnz"):
            if labels.get(index) or labels.get(index + 1):
                continue
            value = pcode.parse_int(first.args[0])
            first_size = pca_line_size(first, insns[index])
            second_size = insns[index + 1].size
            always_taken = (second.op == "jz" and value == 0) or (second.op == "jnz" and value != 0)
            always_not_taken = (second.op == "jz" and value != 0) or (second.op == "jnz" and value == 0)
            if always_taken:
                const_branch_to_jump += 1
                estimated_savings += first_size
            elif always_not_taken:
                const_branch_remove += 1
                estimated_savings += first_size + second_size

    for index, line in enumerate(code):
        if line.op not in BRANCH_OPS:
            continue
        target = label_to_index.get(line.args[0])
        if target is None:
            continue
        if line.op == "jmp" and target == index + 1:
            jump_to_next += 1
            estimated_savings += insns[index].size
        if 0 <= target < len(code) and code[target].op == "jmp":
            branch_to_branch += 1

    temp_rows: list[tuple[str, int, int, int, int, int]] = []
    for temp in sorted(set(temp_loads) | set(temp_stores), key=lambda item: int(item, 0)):
        loads = temp_loads[temp]
        stores = temp_stores[temp]
        temp_rows.append((
            temp,
            loads,
            stores,
            store_load_pairs[temp],
            load_store_pairs[temp],
            removable_by_temp[temp],
        ))
    temp_rows.sort(key=lambda item: item[1] + item[2], reverse=True)

    estimated_savings += sum(removable_by_temp.values()) * 2
    return {
        "temp_slot_accesses": temp_rows,
        "store_load_pairs": sum(store_load_pairs.values()),
        "load_store_pairs": sum(load_store_pairs.values()),
        "removable_store_load_pairs": sum(removable_by_temp.values()),
        "const_branch_to_jump": const_branch_to_jump,
        "const_branch_remove": const_branch_remove,
        "jump_to_next": jump_to_next,
        "branch_to_branch": branch_to_branch,
        "peephole_estimated_savings": estimated_savings,
    }


def analyze_pca(path: pathlib.Path) -> dict[str, object]:
    entry, insns, _labels, data_labels, data = pcode.parse_pca(path)
    lines = read_pca_lines(path)
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
    zlocal_short = 0
    zlocal_s8 = 0
    zlocal_u16 = 0
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
        elif insn.op in ("llocal", "slocal", "zlocal"):
            value = pcode.parse_int(insn.args[0])
            if 0 <= value <= 3:
                if insn.op == "llocal":
                    llocal_short += 1
                elif insn.op == "slocal":
                    slocal_short += 1
                else:
                    zlocal_short += 1
            elif -128 <= value <= 127:
                if insn.op == "llocal":
                    llocal_s8 += 1
                elif insn.op == "slocal":
                    slocal_s8 += 1
                else:
                    zlocal_s8 += 1
            else:
                if insn.op == "llocal":
                    llocal_u16 += 1
                elif insn.op == "slocal":
                    slocal_u16 += 1
                else:
                    zlocal_u16 += 1
        if index + 1 < len(insns):
            next_insn = insns[index + 1]
            if insn.op == "slocal" and next_insn.op == "llocal" and insn.args == next_insn.args:
                temp_roundtrips += 1

    call_count = histogram["call"]
    icall_count = histogram["icall"]
    ncall_count = histogram["ncall"]
    natives = {insn.args[0] for insn in insns if insn.op == "ncall"}

    code, _line_to_code, _code_to_line, _labels_by_code, _functions = build_code_maps(lines)
    function_sizes: Counter[str] = Counter()
    current_function = "(prelude)"
    code_index = 0
    for line in lines:
        if line.op in ("func", "static_func"):
            current_function = line.args[0]
        elif line.op in NON_CODE_OPS or line.op in CODE_LABEL_OPS:
            pass
        else:
            if code_index < len(code):
                function_sizes[current_function] += insns[code_index].size
                code_index += 1

    peephole = analyze_peephole_candidates(lines, insns)

    return {
        "entry": entry,
        "bytecode_bytes": bytecode_bytes,
        "global_data_bytes": len(data),
        "string_literal_bytes": literal_bytes(data, data_labels),
        "native_table_bytes": len(natives) * 2,
        "metadata_bytes": 4,
        "payload_bytes": bytecode_bytes + len(data) + len(natives) * 2,
        "function_count": sum(1 for line in lines if line.op in ("func", "static_func")),
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
        "zlocal_short": zlocal_short,
        "zlocal_s8": zlocal_s8,
        "zlocal_u16": zlocal_u16,
        "temp_slot_accesses": peephole["temp_slot_accesses"],
        "store_load_pairs": peephole["store_load_pairs"],
        "load_store_pairs": peephole["load_store_pairs"],
        "removable_store_load_pairs": peephole["removable_store_load_pairs"],
        "const_branch_to_jump": peephole["const_branch_to_jump"],
        "const_branch_remove": peephole["const_branch_remove"],
        "jump_to_next": peephole["jump_to_next"],
        "branch_to_branch": peephole["branch_to_branch"],
        "peephole_estimated_savings": peephole["peephole_estimated_savings"],
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
        f"sshort={stats['slocal_short']} ss8={stats['slocal_s8']} su16={stats['slocal_u16']} "
        f"zshort={stats['zlocal_short']} zs8={stats['zlocal_s8']} zu16={stats['zlocal_u16']}"
    )
    lines.append(f"{indent}temp store/load roundtrips: {stats['temp_roundtrips']}")
    lines.append(f"{indent}peephole candidates:")
    lines.append(
        f"{indent}  store/load same temp: {stats['store_load_pairs']} "
        f"(current pass removable: {stats['removable_store_load_pairs']})"
    )
    lines.append(f"{indent}  load/store same temp: {stats['load_store_pairs']}")
    lines.append(
        f"{indent}  constant branches: to-jump={stats['const_branch_to_jump']} "
        f"remove={stats['const_branch_remove']}"
    )
    lines.append(
        f"{indent}  jump-to-next={stats['jump_to_next']} "
        f"branch-to-branch={stats['branch_to_branch']}"
    )
    lines.append(f"{indent}  estimated local savings: {stats['peephole_estimated_savings']} bytes")
    lines.append(f"{indent}top local/temp slots:")
    for temp, loads, stores, store_load, load_store, removable in stats["temp_slot_accesses"][:8]:
        lines.append(
            f"{indent}  {temp}: loads={loads} stores={stores} "
            f"store/load={store_load} load/store={load_store} removable={removable}"
        )
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

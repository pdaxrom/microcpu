#!/usr/bin/env python3
"""Measure p-code size for self-host compiler modules."""

from __future__ import annotations

import argparse
import pathlib
import re
import shlex
import subprocess
import sys
from collections import OrderedDict


ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))

from run_pcode_microemu import (  # noqa: E402
    OP_ADDR_GLOBAL_U16,
    OP_ADDR_LOCAL_S8,
    OP_ADDR_LOCAL_U16,
    OP_CALL_U16,
    OP_CALL0_U16,
    OP_CALL1_U16,
    OP_CALL2_U16,
    OP_CALL3_U16,
    OP_ADDI_S8,
    OP_ADDI_U16,
    OP_DROP,
    OP_DUP,
    OP_EQI_S8,
    OP_ICONST_0,
    OP_ICONST_1,
    OP_ICONST_2,
    OP_ICONST_M1,
    OP_ICONST_S8,
    OP_ICONST_U16,
    OP_ICALL_U8,
    OP_JMP_S16,
    OP_JMP_S8,
    OP_JNZ_S16,
    OP_JNZ_S8,
    OP_JZ_S16,
    OP_JZ_S8,
    OP_LGLOBAL_U16,
    OP_LADD_LOCAL0_2,
    OP_LLOCAL_0,
    OP_LLOCAL_S8,
    OP_LLOCAL_U16,
    OP_NCALL_U8,
    OP_LEAVE,
    OP_RET,
    OP_SLOCAL0_S8,
    OP_SLOCAL2_S8,
    OP_SUBI_S8,
    OP_SWAP,
    OP_SGLOBAL_U16,
    OP_SLOCAL_0,
    OP_SLOCAL_S8,
    OP_SLOCAL_U16,
    OP_TLOCAL0,
    OP_ZLOCAL_0,
    OP_ZLOCAL_S8,
    OP_ZLOCAL_U16,
    SIMPLE_OPS,
    WordOperand,
    bytecode_size,
    encode_pca_object,
    emit_u16,
    emit_word_symbol,
    parse_int,
    parse_pca,
    write_encoded_pcode_object_asm,
)
import pcode_opt  # noqa: E402


ERROR_RE = re.compile(r"\*\*\*\* (.*)")
UNSUPPORTED_PCODE_RE = re.compile(r"unsupported internal pcode for stack backend: ([0-9]+)")
LITERAL_LABEL_RE = re.compile(r"^L[0-9]+$")


def shell_join(argv: list[str]) -> str:
    return " ".join(shlex.quote(arg) for arg in argv)


def text_or_empty(value: str | bytes | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("latin-1", errors="replace")
    return value


def read_text(path: pathlib.Path) -> str:
    try:
        return path.read_text(errors="replace")
    except OSError:
        return ""


def read_lines(path: pathlib.Path) -> list[str]:
    text = read_text(path)
    if not text:
        return []
    return text.splitlines()


def write_command_log(
    path: pathlib.Path,
    title: str,
    argv: list[str],
    proc: subprocess.CompletedProcess[str],
) -> None:
    with path.open("a") as fp:
        fp.write(f"== {title} ==\n")
        fp.write(f"$ {shell_join(argv)}\n")
        fp.write(f"exit={proc.returncode}\n")
        if proc.stdout:
            fp.write("-- stdout --\n")
            fp.write(proc.stdout)
            if not proc.stdout.endswith("\n"):
                fp.write("\n")
        if proc.stderr:
            fp.write("-- stderr --\n")
            fp.write(proc.stderr)
            if not proc.stderr.endswith("\n"):
                fp.write("\n")
        fp.write("\n")


def run_cmd(
    log_path: pathlib.Path,
    title: str,
    argv: list[str],
    timeout_seconds: int | None = None,
) -> subprocess.CompletedProcess[str]:
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
        proc = subprocess.CompletedProcess(
            argv,
            124,
            stdout=text_or_empty(exc.stdout),
            stderr=text_or_empty(exc.stderr),
        )
    write_command_log(log_path, title, argv, proc)
    return proc


def first_error(stderr: str) -> tuple[str, str, str]:
    unsupported = UNSUPPORTED_PCODE_RE.search(stderr)
    reason = ""
    opcode = ""
    near = ""
    if unsupported:
        reason = f"unsupported internal pcode for stack backend: {unsupported.group(1)}"
        opcode = unsupported.group(1)
    for line in stderr.splitlines():
        match = ERROR_RE.search(line)
        if match and not reason:
            reason = match.group(1).strip()
    lines = stderr.splitlines()
    for index, line in enumerate(lines):
        if "****" in line and index >= 2:
            near = lines[index - 2].strip()
            break
    if not reason:
        reason = "compiler failed"
    return reason, opcode, near


def insn_size(insn, labels: dict[str, int]) -> int:
    return insn.size


def encode_pca_module(
    path: pathlib.Path,
) -> tuple[int, list[int | WordOperand], list[int], dict[str, int], list[str], list[str]]:
    entry, insns, labels, data_labels, data = parse_pca(path)
    entry_addr = labels[entry] if entry in labels else 0
    out: list[int | WordOperand] = []
    native_ids: "OrderedDict[str, int]" = OrderedDict()
    externs: "OrderedDict[str, int]" = OrderedDict()
    for insn in insns:
        op = insn.op
        args = insn.args
        if op == "iconst":
            value = parse_int(args[0])
            if value == -1:
                out.append(OP_ICONST_M1)
            elif value == 0:
                out.append(OP_ICONST_0)
            elif value == 1:
                out.append(OP_ICONST_1)
            elif value == 2:
                out.append(OP_ICONST_2)
            elif -128 <= value <= 127:
                out.extend([OP_ICONST_S8, value & 0xFF])
            else:
                out.append(OP_ICONST_U16)
                emit_u16(out, value)
        elif op == "addi":
            value = parse_int(args[0])
            if not -128 <= value <= 127:
                raise ValueError(f"addi operand out of range: {value}")
            out.extend([OP_ADDI_S8, value & 0xFF])
        elif op == "addi_u16":
            value = parse_int(args[0])
            out.append(OP_ADDI_U16)
            emit_u16(out, value)
        elif op == "subi":
            value = parse_int(args[0])
            if not -128 <= value <= 127:
                raise ValueError(f"subi operand out of range: {value}")
            out.extend([OP_SUBI_S8, value & 0xFF])
        elif op == "eqi":
            value = parse_int(args[0])
            if not -128 <= value <= 127:
                raise ValueError(f"eqi operand out of range: {value}")
            out.extend([OP_EQI_S8, value & 0xFF])
        elif op == "slocal0_s8":
            value = parse_int(args[0])
            if not -128 <= value <= 127:
                raise ValueError(f"slocal0_s8 operand out of range: {value}")
            out.extend([OP_SLOCAL0_S8, value & 0xFF])
        elif op == "slocal2_s8":
            value = parse_int(args[0])
            if not -128 <= value <= 127:
                raise ValueError(f"slocal2_s8 operand out of range: {value}")
            out.extend([OP_SLOCAL2_S8, value & 0xFF])
        elif op == "ladd_local0_2":
            out.append(OP_LADD_LOCAL0_2)
        elif op == "tlocal0":
            out.append(OP_TLOCAL0)
        elif op in ("llocal", "slocal", "zlocal"):
            value = parse_int(args[0])
            if op == "llocal" and 0 <= value <= 3:
                out.append(OP_LLOCAL_0 + value)
            elif op == "slocal" and 0 <= value <= 3:
                out.append(OP_SLOCAL_0 + value)
            elif op == "zlocal" and 0 <= value <= 3:
                out.append(OP_ZLOCAL_0 + value)
            elif -128 <= value <= 127:
                if op == "llocal":
                    out.extend([OP_LLOCAL_S8, value & 0xFF])
                elif op == "slocal":
                    out.extend([OP_SLOCAL_S8, value & 0xFF])
                else:
                    out.extend([OP_ZLOCAL_S8, value & 0xFF])
            else:
                if op == "llocal":
                    out.append(OP_LLOCAL_U16)
                elif op == "slocal":
                    out.append(OP_SLOCAL_U16)
                else:
                    out.append(OP_ZLOCAL_U16)
                emit_u16(out, value)
        elif op == "addr_local":
            value = parse_int(args[0])
            if -128 <= value <= 127:
                out.extend([OP_ADDR_LOCAL_S8, value & 0xFF])
            else:
                out.append(OP_ADDR_LOCAL_U16)
                emit_u16(out, value)
        elif op in ("lglobal", "sglobal", "addr_global"):
            out.append({
                "lglobal": OP_LGLOBAL_U16,
                "sglobal": OP_SGLOBAL_U16,
                "addr_global": OP_ADDR_GLOBAL_U16,
            }[op])
            if args[0] not in data_labels:
                externs[args[0]] = 1
            emit_word_symbol(out, args[0])
        elif op == "addr_func":
            out.append(OP_ICONST_U16)
            emit_u16(out, labels[args[0]])
        elif op in ("jmp", "jz", "jnz"):
            target = labels[args[0]]
            if insn.size == 2:
                opcode = {"jmp": OP_JMP_S8, "jz": OP_JZ_S8, "jnz": OP_JNZ_S8}[op]
                rel = target - (insn.addr + 2)
                out.extend([opcode, rel & 0xFF])
            else:
                opcode = {"jmp": OP_JMP_S16, "jz": OP_JZ_S16, "jnz": OP_JNZ_S16}[op]
                rel = target - (insn.addr + 3)
                out.append(opcode)
                emit_u16(out, rel)
        elif op == "call":
            argc = parse_int(args[1])
            if args[0] not in labels:
                native = args[0]
                if native not in native_ids:
                    native_ids[native] = len(native_ids)
                    externs[native] = 1
                out.extend([OP_NCALL_U8, native_ids[native], argc & 0xFF])
            else:
                if 0 <= argc <= 2:
                    out.append([OP_CALL0_U16, OP_CALL1_U16, OP_CALL2_U16][argc])
                    emit_u16(out, labels[args[0]])
                elif argc == 3:
                    out.append(OP_CALL3_U16)
                    emit_u16(out, labels[args[0]])
                else:
                    out.append(OP_CALL_U16)
                    emit_u16(out, labels[args[0]])
                    out.append(argc & 0xFF)
        elif op == "icall":
            out.extend([OP_ICALL_U8, parse_int(args[0]) & 0xFF])
        elif op == "ncall":
            native = args[0]
            if native not in native_ids:
                native_ids[native] = len(native_ids)
                externs[native] = 1
            native_id = native_ids[native]
            if native_id > 255:
                raise ValueError("NCALL_U16 is not supported by the microcpu p-code interpreter yet")
            out.extend([OP_NCALL_U8, native_id, parse_int(args[1]) & 0xFF])
        elif op == "ret":
            out.append(OP_RET)
        elif op == "drop":
            out.append(OP_DROP)
        elif op == "dup":
            out.append(OP_DUP)
        elif op == "swap":
            out.append(OP_SWAP)
        elif op == "leave":
            out.append(OP_LEAVE)
        elif op in SIMPLE_OPS:
            out.append(SIMPLE_OPS[op])
        else:
            raise ValueError(f"unsupported p-code op for object encoding: {op}")
    return entry_addr, out, data, data_labels, list(native_ids.keys()), list(externs.keys())


def pca_counts(path: pathlib.Path) -> dict[str, int]:
    functions = 0
    native_calls = 0
    indirect_calls = 0
    for line in read_lines(path):
        stripped = line.strip()
        if stripped.startswith("func ") or stripped.startswith("static_func "):
            functions += 1
        elif stripped.startswith("ncall "):
            native_calls += 1
        elif stripped.startswith("icall "):
            indirect_calls += 1
    return {"functions": functions, "native_calls": native_calls, "indirect_calls": indirect_calls}


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


def global_count(data_labels: dict[str, int]) -> int:
    count = 0
    for label in data_labels:
        if not LITERAL_LABEL_RE.match(label):
            count += 1
    return count


def assemble_object(
    assembler: pathlib.Path,
    asm_path: pathlib.Path,
    obj_path: pathlib.Path,
    log_path: pathlib.Path,
) -> tuple[bool, int]:
    proc = run_cmd(log_path, "assemble-object", [str(assembler), "-object", str(asm_path), str(obj_path)])
    if proc.returncode == 0 and obj_path.exists():
        return True, obj_path.stat().st_size
    return False, 0


def compile_one(source: pathlib.Path, args: argparse.Namespace) -> dict[str, object]:
    name = source.stem
    log_path = args.build_dir / f"{name}.log"
    i_path = args.build_dir / f"{name}.i"
    pca_path = args.build_dir / f"{name}.pca"
    pcode_asm = args.build_dir / f"{name}.pcode.asm"
    pcode_obj = args.build_dir / f"{name}.pcode.o"
    native_asm = args.build_dir / f"{name}.native.asm"
    native_obj = args.build_dir / f"{name}.native.o"
    log_path.write_text("")

    result: dict[str, object] = {
        "name": name,
        "source": source,
        "log": log_path,
        "pcode_ok": False,
        "pcode_obj_ok": False,
        "native_ok": False,
        "native_obj_size": 0,
        "reason": "",
        "unsupported_opcode": "",
        "near": "",
        "bytecode_bytes": 0,
        "global_data_bytes": 0,
        "literal_bytes": 0,
        "native_table_bytes": 0,
        "functions": 0,
        "native_calls": 0,
        "indirect_calls": 0,
        "native_entries": 0,
        "globals": 0,
        "pcode_obj_size": 0,
        "payload_bytes": 0,
        "natives": [],
        "pcode_opt": False,
        "pcode_opt_removed": 0,
        "pcode_opt_rewritten": 0,
        "pcode_opt_const_to_jump": 0,
        "pcode_opt_const_removed": 0,
        "pcode_opt_jump_next": 0,
        "pcode_opt_cond_next": 0,
        "pcode_opt_inverted": 0,
        "pcode_opt_branch_threaded": 0,
        "pcode_opt_addi": 0,
        "pcode_opt_addiu16": 0,
        "pcode_opt_subi": 0,
        "pcode_opt_eqi": 0,
        "pcode_opt_slocal_const": 0,
        "pcode_opt_zlocal": 0,
        "pcode_opt_ladd_local0_2": 0,
        "pcode_opt_tlocal0": 0,
        "pcode_opt_saved": 0,
        "pcode_opt_before": 0,
        "pcode_opt_after": 0,
        "peephole_estimated_savings": 0,
        "store_load_pairs": 0,
        "removable_store_load_pairs": 0,
        "load_store_pairs": 0,
        "const_branch_to_jump": 0,
        "const_branch_remove": 0,
        "jump_to_next": 0,
        "branch_to_branch": 0,
    }

    argv = [str(args.preprocessor), "-o", str(i_path)]
    for define in args.define:
        argv.extend(["-D", define])
    for include_dir in args.include_dir:
        argv.extend(["-I", str(include_dir)])
    argv.append(str(source))
    proc = run_cmd(log_path, "preprocess", argv, args.timeout_seconds)
    if proc.returncode != 0:
        result["reason"] = "preprocess failed"
        return result

    argv = [str(args.cc_only), "--backend", "pcode", "-o", str(pca_path), str(i_path)]
    proc = run_cmd(log_path, "compile-pcode", argv, args.timeout_seconds)
    if proc.returncode != 0 or ERROR_RE.search(proc.stderr) or UNSUPPORTED_PCODE_RE.search(proc.stderr):
        reason, opcode, near = first_error(proc.stderr)
        result["reason"] = reason
        result["unsupported_opcode"] = opcode
        result["near"] = near
    else:
        try:
            if args.pcode_opt:
                raw_pca_path = args.build_dir / f"{name}.raw.pca"
                pca_path.replace(raw_pca_path)
                opt_stats = pcode_opt.optimize_pca_file(raw_pca_path, pca_path)
                result.update({
                    "pcode_opt": True,
                    "pcode_opt_removed": opt_stats["removed_temp_roundtrips"],
                    "pcode_opt_rewritten": opt_stats["rewritten_store_load_roundtrips"],
                    "pcode_opt_const_to_jump": opt_stats["const_branch_to_jump"],
                    "pcode_opt_const_removed": opt_stats["const_branch_removed"],
                    "pcode_opt_jump_next": opt_stats["jump_to_next_removed"],
                    "pcode_opt_cond_next": opt_stats["cond_to_next_replaced"],
                    "pcode_opt_inverted": opt_stats["inverted_branch_jumps"],
                    "pcode_opt_branch_threaded": opt_stats["branch_threaded"],
                    "pcode_opt_addi": opt_stats["addi_s8_rewrites"],
                    "pcode_opt_addiu16": opt_stats["addi_u16_rewrites"],
                    "pcode_opt_subi": opt_stats["subi_s8_rewrites"],
                    "pcode_opt_eqi": opt_stats["eqi_s8_rewrites"],
                    "pcode_opt_slocal_const": opt_stats["slocal_const_s8_rewrites"],
                    "pcode_opt_zlocal": opt_stats["zlocal_rewrites"],
                    "pcode_opt_ladd_local0_2": opt_stats["ladd_local0_2_rewrites"],
                    "pcode_opt_tlocal0": opt_stats["tlocal0_rewrites"],
                    "pcode_opt_saved": opt_stats["bytecode_saved"],
                    "pcode_opt_before": opt_stats["bytecode_before"],
                    "pcode_opt_after": opt_stats["bytecode_after"],
                })
                with log_path.open("a") as log:
                    log.write("== pcode-opt ==\n")
                    log.write(f"removed_temp_roundtrips={opt_stats['removed_temp_roundtrips']}\n")
                    log.write(f"rewritten_store_load_roundtrips={opt_stats['rewritten_store_load_roundtrips']}\n")
                    log.write(f"rewrite_byte_savings={opt_stats['rewrite_byte_savings']}\n")
                    log.write(f"const_branch_to_jump={opt_stats['const_branch_to_jump']}\n")
                    log.write(f"const_branch_removed={opt_stats['const_branch_removed']}\n")
                    log.write(f"jump_to_next_removed={opt_stats['jump_to_next_removed']}\n")
                    log.write(f"cond_to_next_replaced={opt_stats['cond_to_next_replaced']}\n")
                    log.write(f"inverted_branch_jumps={opt_stats['inverted_branch_jumps']}\n")
                    log.write(f"branch_threaded={opt_stats['branch_threaded']}\n")
                    log.write(f"branch_thread_byte_savings={opt_stats['branch_thread_byte_savings']}\n")
                    log.write(f"addi_s8_rewrites={opt_stats['addi_s8_rewrites']}\n")
                    log.write(f"addi_u16_rewrites={opt_stats['addi_u16_rewrites']}\n")
                    log.write(f"subi_s8_rewrites={opt_stats['subi_s8_rewrites']}\n")
                    log.write(f"eqi_s8_rewrites={opt_stats['eqi_s8_rewrites']}\n")
                    log.write(f"slocal_const_s8_rewrites={opt_stats['slocal_const_s8_rewrites']}\n")
                    log.write(f"zlocal_rewrites={opt_stats['zlocal_rewrites']}\n")
                    log.write(f"ladd_local0_2_rewrites={opt_stats['ladd_local0_2_rewrites']}\n")
                    log.write(f"tlocal0_rewrites={opt_stats['tlocal0_rewrites']}\n")
                    log.write(f"bytecode_before={opt_stats['bytecode_before']}\n")
                    log.write(f"bytecode_after={opt_stats['bytecode_after']}\n")
                    log.write(f"bytecode_saved={opt_stats['bytecode_saved']}\n\n")
            encoded = encode_pca_object(pca_path)
            write_encoded_pcode_object_asm(pcode_asm, encoded, name)
            pcode_obj_ok, pcode_obj_size = assemble_object(args.assembler, pcode_asm, pcode_obj, log_path)
            counts = pca_counts(pca_path)
            analysis = pcode_opt.analyze_pca(pca_path)
            bytecode_bytes = bytecode_size(encoded.bytecode)
            native_table_bytes = 0
            result.update({
                "pcode_ok": True,
                "pcode_obj_ok": pcode_obj_ok,
                "bytecode_bytes": bytecode_bytes,
                "global_data_bytes": len(encoded.data),
                "literal_bytes": literal_bytes(encoded.data, encoded.data_labels),
                "native_table_bytes": native_table_bytes,
                "functions": counts["functions"],
                "native_calls": counts["native_calls"],
                "indirect_calls": counts["indirect_calls"],
                "native_entries": len(encoded.natives),
                "globals": global_count(encoded.data_labels),
                "pcode_obj_size": pcode_obj_size,
                "payload_bytes": bytecode_bytes + len(encoded.data) + native_table_bytes,
                "natives": encoded.natives,
                "peephole_estimated_savings": int(analysis["peephole_estimated_savings"]),
                "store_load_pairs": int(analysis["store_load_pairs"]),
                "removable_store_load_pairs": int(analysis["removable_store_load_pairs"]),
                "load_store_pairs": int(analysis["load_store_pairs"]),
                "const_branch_to_jump": int(analysis["const_branch_to_jump"]),
                "const_branch_remove": int(analysis["const_branch_remove"]),
                "jump_to_next": int(analysis["jump_to_next"]),
                "branch_to_branch": int(analysis["branch_to_branch"]),
            })
            if not pcode_obj_ok:
                result["reason"] = "p-code object assembly failed"
        except Exception as exc:
            result["reason"] = str(exc)

    argv = [str(args.cc_only), "--backend", "microcpu", "--object", "-o", str(native_asm), str(i_path)]
    proc = run_cmd(log_path, "compile-native-object", argv, args.timeout_seconds)
    if proc.returncode == 0:
        native_ok, native_size = assemble_object(args.assembler, native_asm, native_obj, log_path)
        result["native_ok"] = native_ok
        result["native_obj_size"] = native_size
    return result


def assemble_runtime_objects(args: argparse.Namespace) -> dict[str, int]:
    sizes: dict[str, int] = {}
    runtime_specs = [
        ("pcode_interpreter.o", args.runtime_dir / "pcode_interpreter.asm"),
        ("runtime_object.o", args.runtime_dir / "runtime_object.asm"),
    ]
    for name, source in runtime_specs:
        log_path = args.build_dir / f"__{name}.log"
        obj_path = args.build_dir / name
        log_path.write_text("")
        ok, size = assemble_object(args.assembler, source, obj_path, log_path)
        sizes[name] = size if ok else 0
    return sizes


def unique_sources(paths: list[pathlib.Path]) -> list[pathlib.Path]:
    out: list[pathlib.Path] = []
    seen: set[str] = set()
    for path in paths:
        key = str(path)
        if key in seen:
            continue
        seen.add(key)
        out.append(path)
    return out


def sum_for_group(results: dict[str, dict[str, object]], sources: list[pathlib.Path]) -> dict[str, int]:
    total = {
        "bytecode": 0,
        "data": 0,
        "literal": 0,
        "native_table": 0,
        "payload": 0,
        "pcode_obj": 0,
        "native_obj": 0,
        "functions": 0,
        "native_calls": 0,
        "indirect_calls": 0,
        "native_entries": 0,
        "globals": 0,
        "failed": 0,
        "opt_removed": 0,
        "opt_rewritten": 0,
        "opt_const_to_jump": 0,
        "opt_const_removed": 0,
        "opt_jump_next": 0,
        "opt_cond_next": 0,
        "opt_inverted": 0,
        "opt_branch_threaded": 0,
        "opt_addi": 0,
        "opt_addiu16": 0,
        "opt_subi": 0,
        "opt_eqi": 0,
        "opt_slocal_const": 0,
        "opt_zlocal": 0,
        "opt_ladd_local0_2": 0,
        "opt_tlocal0": 0,
        "opt_saved": 0,
        "peephole_estimated_savings": 0,
        "store_load_pairs": 0,
        "removable_store_load_pairs": 0,
        "load_store_pairs": 0,
        "const_branch_to_jump": 0,
        "const_branch_remove": 0,
        "jump_to_next": 0,
        "branch_to_branch": 0,
    }
    for source in sources:
        item = results[source.stem]
        if not item["pcode_ok"]:
            total["failed"] += 1
        total["bytecode"] += int(item["bytecode_bytes"])
        total["data"] += int(item["global_data_bytes"])
        total["literal"] += int(item["literal_bytes"])
        total["native_table"] += int(item["native_table_bytes"])
        total["payload"] += int(item["payload_bytes"])
        total["pcode_obj"] += int(item["pcode_obj_size"])
        total["native_obj"] += int(item["native_obj_size"])
        total["functions"] += int(item["functions"])
        total["native_calls"] += int(item["native_calls"])
        total["indirect_calls"] += int(item["indirect_calls"])
        total["native_entries"] += int(item["native_entries"])
        total["globals"] += int(item["globals"])
        total["opt_removed"] += int(item["pcode_opt_removed"])
        total["opt_rewritten"] += int(item["pcode_opt_rewritten"])
        total["opt_const_to_jump"] += int(item["pcode_opt_const_to_jump"])
        total["opt_const_removed"] += int(item["pcode_opt_const_removed"])
        total["opt_jump_next"] += int(item["pcode_opt_jump_next"])
        total["opt_cond_next"] += int(item["pcode_opt_cond_next"])
        total["opt_inverted"] += int(item["pcode_opt_inverted"])
        total["opt_branch_threaded"] += int(item["pcode_opt_branch_threaded"])
        total["opt_addi"] += int(item["pcode_opt_addi"])
        total["opt_addiu16"] += int(item["pcode_opt_addiu16"])
        total["opt_subi"] += int(item["pcode_opt_subi"])
        total["opt_eqi"] += int(item["pcode_opt_eqi"])
        total["opt_slocal_const"] += int(item["pcode_opt_slocal_const"])
        total["opt_zlocal"] += int(item["pcode_opt_zlocal"])
        total["opt_ladd_local0_2"] += int(item["pcode_opt_ladd_local0_2"])
        total["opt_tlocal0"] += int(item["pcode_opt_tlocal0"])
        total["opt_saved"] += int(item["pcode_opt_saved"])
        total["peephole_estimated_savings"] += int(item["peephole_estimated_savings"])
        total["store_load_pairs"] += int(item["store_load_pairs"])
        total["removable_store_load_pairs"] += int(item["removable_store_load_pairs"])
        total["load_store_pairs"] += int(item["load_store_pairs"])
        total["const_branch_to_jump"] += int(item["const_branch_to_jump"])
        total["const_branch_remove"] += int(item["const_branch_remove"])
        total["jump_to_next"] += int(item["jump_to_next"])
        total["branch_to_branch"] += int(item["branch_to_branch"])
    return total


def write_module_report(fp, result: dict[str, object], interp_size: int, runtime_size: int) -> None:
    fp.write(f"{result['name']}:\n")
    fp.write(f"  source: {result['source']}\n")
    fp.write(f"  p-code generation: {'PASS' if result['pcode_ok'] else 'FAIL'}\n")
    if not result["pcode_ok"]:
        fp.write(f"  reason: {result['reason']}\n")
        if result["unsupported_opcode"]:
            fp.write(f"  unsupported internal pcode: {result['unsupported_opcode']}\n")
        if result["near"]:
            fp.write(f"  near: {result['near']}\n")
        fp.write("  suggested next lowering support: inspect the unsupported pseudo-code and add the smallest stack-VM translation\n")
    fp.write(f"  p-code bytecode bytes: {result['bytecode_bytes']}\n")
    if result["pcode_opt"]:
        fp.write("  p-code optimizer: enabled\n")
        fp.write(f"  optimizer removed temp store/load pairs: {result['pcode_opt_removed']}\n")
        fp.write(f"  optimizer rewrote live temp store/load pairs: {result['pcode_opt_rewritten']}\n")
        fp.write(f"  optimizer constant branches to jumps: {result['pcode_opt_const_to_jump']}\n")
        fp.write(f"  optimizer constant branches removed: {result['pcode_opt_const_removed']}\n")
        fp.write(f"  optimizer jumps to next removed: {result['pcode_opt_jump_next']}\n")
        fp.write(f"  optimizer conditional branches to next replaced: {result['pcode_opt_cond_next']}\n")
        fp.write(f"  optimizer inverted branch/jump pairs: {result['pcode_opt_inverted']}\n")
        fp.write(f"  optimizer threaded branches: {result['pcode_opt_branch_threaded']}\n")
        fp.write(f"  optimizer iconst/add to addi_s8 rewrites: {result['pcode_opt_addi']}\n")
        fp.write(f"  optimizer iconst/add to addi_u16 rewrites: {result['pcode_opt_addiu16']}\n")
        fp.write(f"  optimizer iconst/sub to subi_s8 rewrites: {result['pcode_opt_subi']}\n")
        fp.write(f"  optimizer iconst/eq to eqi_s8 rewrites: {result['pcode_opt_eqi']}\n")
        fp.write(f"  optimizer iconst/slocal0,2 to slocal*_s8 rewrites: {result['pcode_opt_slocal_const']}\n")
        fp.write(f"  optimizer iconst-zero/slocal to zlocal rewrites: {result['pcode_opt_zlocal']}\n")
        fp.write(f"  optimizer llocal0/llocal2/add rewrites: {result['pcode_opt_ladd_local0_2']}\n")
        fp.write(f"  optimizer slocal0/llocal0 to tlocal0 rewrites: {result['pcode_opt_tlocal0']}\n")
        fp.write(f"  optimizer bytecode before: {result['pcode_opt_before']}\n")
        fp.write(f"  optimizer bytecode after: {result['pcode_opt_after']}\n")
        fp.write(f"  optimizer bytecode saved: {result['pcode_opt_saved']}\n")
    else:
        fp.write("  p-code optimizer: disabled\n")
    fp.write("  peephole diagnostics:\n")
    fp.write(f"    store/load same temp: {result['store_load_pairs']}\n")
    fp.write(f"    current pass removable: {result['removable_store_load_pairs']}\n")
    fp.write(f"    load/store same temp: {result['load_store_pairs']}\n")
    fp.write(f"    constant branches to jump: {result['const_branch_to_jump']}\n")
    fp.write(f"    constant branches removable: {result['const_branch_remove']}\n")
    fp.write(f"    jump-to-next: {result['jump_to_next']}\n")
    fp.write(f"    branch-to-branch: {result['branch_to_branch']}\n")
    fp.write(f"    estimated local savings: {result['peephole_estimated_savings']} bytes\n")
    fp.write(f"  p-code global data bytes: {result['global_data_bytes']}\n")
    fp.write(f"  string/literal bytes: {result['literal_bytes']}\n")
    fp.write(f"  native call table bytes: {result['native_table_bytes']}\n")
    fp.write(f"  p-code functions: {result['functions']}\n")
    fp.write(f"  native call instructions: {result['native_calls']}\n")
    fp.write(f"  indirect call instructions: {result['indirect_calls']}\n")
    fp.write(f"  native table entries: {result['native_entries']}\n")
    fp.write(f"  globals: {result['globals']}\n")
    fp.write(f"  pcode.o size: {result['pcode_obj_size'] if result['pcode_obj_ok'] else 'unavailable'}\n")
    fp.write(f"  equivalent native object size: {result['native_obj_size'] if result['native_ok'] else 'unavailable'}\n")
    standalone = interp_size + int(result["payload_bytes"])
    if int(result["native_entries"]) > 0:
        standalone += runtime_size
    fp.write(f"  estimated standalone p-code linked bytes: {standalone}\n")
    natives = result["natives"]
    if natives:
        fp.write("  native symbols:\n")
        for native in natives[:20]:
            fp.write(f"    {native}\n")
        if len(natives) > 20:
            fp.write(f"    ... {len(natives) - 20} more\n")
    fp.write(f"  log: {result['log']}\n\n")


def write_group_report(
    fp,
    name: str,
    total: dict[str, int],
    interp_size: int,
    runtime_size: int,
) -> None:
    needs_runtime = total["native_entries"] > 0
    pcode_est = interp_size + total["payload"] + (runtime_size if needs_runtime else 0)
    native_total = total["native_obj"]
    fp.write(f"{name}:\n")
    fp.write(f"  modules with p-code failures: {total['failed']}\n")
    fp.write(f"  pcode_interpreter.o size: {interp_size}\n")
    fp.write(f"  runtime/libc object estimate: {runtime_size if needs_runtime else 0}\n")
    fp.write(f"  p-code bytecode bytes: {total['bytecode']}\n")
    fp.write(f"  optimizer removed temp store/load pairs: {total['opt_removed']}\n")
    fp.write(f"  optimizer rewrote live temp store/load pairs: {total['opt_rewritten']}\n")
    fp.write(f"  optimizer constant branches to jumps: {total['opt_const_to_jump']}\n")
    fp.write(f"  optimizer constant branches removed: {total['opt_const_removed']}\n")
    fp.write(f"  optimizer jumps to next removed: {total['opt_jump_next']}\n")
    fp.write(f"  optimizer conditional branches to next replaced: {total['opt_cond_next']}\n")
    fp.write(f"  optimizer inverted branch/jump pairs: {total['opt_inverted']}\n")
    fp.write(f"  optimizer threaded branches: {total['opt_branch_threaded']}\n")
    fp.write(f"  optimizer iconst/add to addi_s8 rewrites: {total['opt_addi']}\n")
    fp.write(f"  optimizer iconst/add to addi_u16 rewrites: {total['opt_addiu16']}\n")
    fp.write(f"  optimizer iconst/sub to subi_s8 rewrites: {total['opt_subi']}\n")
    fp.write(f"  optimizer iconst/eq to eqi_s8 rewrites: {total['opt_eqi']}\n")
    fp.write(f"  optimizer iconst/slocal0,2 to slocal*_s8 rewrites: {total['opt_slocal_const']}\n")
    fp.write(f"  optimizer iconst-zero/slocal to zlocal rewrites: {total['opt_zlocal']}\n")
    fp.write(f"  optimizer llocal0/llocal2/add rewrites: {total['opt_ladd_local0_2']}\n")
    fp.write(f"  optimizer slocal0/llocal0 to tlocal0 rewrites: {total['opt_tlocal0']}\n")
    fp.write(f"  optimizer bytecode saved: {total['opt_saved']}\n")
    fp.write("  peephole candidates after current optimizer:\n")
    fp.write(f"    store/load same temp: {total['store_load_pairs']}\n")
    fp.write(f"    current pass removable: {total['removable_store_load_pairs']}\n")
    fp.write(f"    load/store same temp: {total['load_store_pairs']}\n")
    fp.write(f"    constant branches to jump: {total['const_branch_to_jump']}\n")
    fp.write(f"    constant branches removable: {total['const_branch_remove']}\n")
    fp.write(f"    jump-to-next: {total['jump_to_next']}\n")
    fp.write(f"    branch-to-branch: {total['branch_to_branch']}\n")
    fp.write(f"    estimated local savings: {total['peephole_estimated_savings']} bytes\n")
    fp.write(f"  p-code global data bytes: {total['data']}\n")
    fp.write(f"  string/literal bytes: {total['literal']}\n")
    fp.write(f"  native call table bytes: {total['native_table']}\n")
    fp.write(f"  p-code payload bytes: {total['payload']}\n")
    fp.write(f"  pcode.o object bytes: {total['pcode_obj']}\n")
    fp.write(f"  p-code functions: {total['functions']}\n")
    fp.write(f"  native call instructions: {total['native_calls']}\n")
    fp.write(f"  indirect call instructions: {total['indirect_calls']}\n")
    fp.write(f"  native table entries: {total['native_entries']}\n")
    fp.write(f"  globals: {total['globals']}\n")
    fp.write(f"  estimated p-code linked bytes: {pcode_est}\n")
    fp.write(f"  native object bytes: {native_total}\n")
    if native_total:
        diff = native_total - pcode_est
        pct = (diff * 100.0) / native_total
        direction = "smaller" if diff >= 0 else "larger"
        fp.write(f"  p-code estimate: {abs(diff)} bytes {direction} than native objects ({abs(pct):.1f}%)\n")
    fp.write("\n")


def write_report(
    args: argparse.Namespace,
    results: dict[str, dict[str, object]],
    runtime_sizes: dict[str, int],
) -> None:
    report = args.build_dir / "size-report.txt"
    interp_size = runtime_sizes.get("pcode_interpreter.o", 0)
    runtime_size = runtime_sizes.get("runtime_object.o", 0)
    smallcpp_total = sum_for_group(results, args.smallcpp_srcs)
    smallcc_total = sum_for_group(results, args.smallcc_srcs)
    with report.open("w") as fp:
        fp.write("Self-host p-code size smoke report\n")
        fp.write(f"Strict: {'yes' if args.strict else 'no'}\n")
        fp.write("\n")
        fp.write("1. Per module p-code size\n\n")
        for source in unique_sources(args.smallcpp_srcs + args.smallcc_srcs):
            write_module_report(fp, results[source.stem], interp_size, runtime_size)
        fp.write("2. Per module native object size\n\n")
        for source in unique_sources(args.smallcpp_srcs + args.smallcc_srcs):
            item = results[source.stem]
            fp.write(f"{item['name']}: {item['native_obj_size'] if item['native_ok'] else 'unavailable'} bytes\n")
        fp.write("\n")
        fp.write("3. Estimated smallcc p-code image\n\n")
        write_group_report(fp, "smallcc", smallcc_total, interp_size, runtime_size)
        fp.write("4. Estimated smallcpp p-code image\n\n")
        write_group_report(fp, "smallcpp", smallcpp_total, interp_size, runtime_size)
        fp.write("5. Comparison against native selfhost-link-smoke\n\n")
        native_report = read_text(args.native_link_report)
        if native_report:
            for line in native_report.splitlines():
                fp.write(f"  {line}\n")
        else:
            fp.write(f"  native link report unavailable: {args.native_link_report}\n")
            fp.write("  run make -C smallc-microcpu selfhost-link-smoke for link status\n")
        fp.write("\n")
        fp.write("6. Conclusion\n\n")
        for name, total in [("smallcpp", smallcpp_total), ("smallcc", smallcc_total)]:
            needs_runtime = total["native_entries"] > 0
            pcode_est = interp_size + total["payload"] + (runtime_size if needs_runtime else 0)
            native_total = total["native_obj"]
            if total["failed"]:
                fp.write(f"- {name}: p-code measurement is incomplete; {total['failed']} module(s) failed p-code generation.\n")
            elif native_total:
                diff = native_total - pcode_est
                direction = "smaller" if diff >= 0 else "larger"
                fp.write(f"- {name}: p-code estimate is {abs(diff)} bytes {direction} than the sum of native objects.\n")
            else:
                fp.write(f"- {name}: native comparison is unavailable.\n")
        fp.write("- This is a size smoke only; it does not link or run a p-code-hosted compiler image.\n")
        fp.write("- Remaining blockers are target-hosted file I/O/argv support, runtime RAM footprint, and final image layout.\n")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preprocessor", required=True, type=pathlib.Path)
    parser.add_argument("--cc-only", required=True, type=pathlib.Path)
    parser.add_argument("--assembler", required=True, type=pathlib.Path)
    parser.add_argument("--runtime-dir", required=True, type=pathlib.Path)
    parser.add_argument("--build-dir", required=True, type=pathlib.Path)
    parser.add_argument("--native-link-report", required=True, type=pathlib.Path)
    parser.add_argument("--include-dir", action="append", default=[], type=pathlib.Path)
    parser.add_argument("--define", action="append", default=[])
    parser.add_argument("--timeout-seconds", default=3, type=int)
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--pcode-opt", action="store_true")
    parser.add_argument("--smallcpp-srcs", nargs="+", required=True, type=pathlib.Path)
    parser.add_argument("--smallcc-srcs", nargs="+", required=True, type=pathlib.Path)
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    args.build_dir.mkdir(parents=True, exist_ok=True)
    runtime_sizes = assemble_runtime_objects(args)
    sources = unique_sources(args.smallcpp_srcs + args.smallcc_srcs)
    results: dict[str, dict[str, object]] = {}
    ok = True
    for source in sources:
        result = compile_one(source, args)
        results[source.stem] = result
        module_ok = bool(result["pcode_ok"])
        ok = ok and module_ok
        print(f"{source.stem}: {'PASS' if module_ok else 'FAIL'}")
        if not module_ok:
            print(f"  reason: {result['reason']}")
            print(f"  log: {result['log']}")
    write_report(args, results, runtime_sizes)
    print(f"report: {args.build_dir / 'size-report.txt'}")
    if args.strict and not ok:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

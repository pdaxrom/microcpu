#!/usr/bin/env python3
"""Run experimental p-code programs through the microcpu p-code interpreter."""

from __future__ import annotations

import argparse
import pathlib
import re
import shlex
import subprocess
import sys
from collections import OrderedDict


REG_RE = re.compile(r"\b(?:v0|r3)=([0-9a-fA-F]{4})\b")
WordOperand = tuple[str, str]
LOCAL_LABEL_RE = re.compile(r"^L[0-9]+$")

OP_ICONST_M1 = 0x02
OP_ICONST_0 = 0x03
OP_ICONST_1 = 0x04
OP_ICONST_2 = 0x05
OP_ICONST_S8 = 0x06
OP_ICONST_U16 = 0x07
OP_DROP = 0x08
OP_DUP = 0x09
OP_SWAP = 0x0A
OP_LLOCAL_0 = 0x10
OP_LLOCAL_1 = 0x11
OP_LLOCAL_2 = 0x12
OP_LLOCAL_3 = 0x13
OP_SLOCAL_0 = 0x14
OP_SLOCAL_1 = 0x15
OP_SLOCAL_2 = 0x16
OP_SLOCAL_3 = 0x17
OP_LLOCAL_S8 = 0x18
OP_SLOCAL_S8 = 0x19
OP_LLOCAL_U16 = 0x1A
OP_SLOCAL_U16 = 0x1B
OP_ADDR_LOCAL_S8 = 0x1C
OP_ADDR_LOCAL_U16 = 0x1D
OP_LGLOBAL_U16 = 0x20
OP_SGLOBAL_U16 = 0x21
OP_ADDR_GLOBAL_U16 = 0x22
OP_LBYTE = 0x30
OP_SBYTE = 0x31
OP_LWORD = 0x32
OP_SWORD = 0x33
OP_JMP_S8 = 0x40
OP_JMP_S16 = 0x41
OP_JZ_S8 = 0x42
OP_JZ_S16 = 0x43
OP_JNZ_S8 = 0x44
OP_JNZ_S16 = 0x45
OP_CALL_U16 = 0x50
OP_RET = 0x51
OP_NCALL_U8 = 0x54
OP_NCALL_U16 = 0x55
OP_NCALL_ADDR_U16 = 0x55
OP_LEAVE = 0x56
OP_ICALL_U8 = 0x57
OP_CALL0_U16 = 0x58
OP_CALL1_U16 = 0x59
OP_CALL2_U16 = 0x5A
OP_NCALL0_ADDR_U16 = 0x5B
OP_NCALL1_ADDR_U16 = 0x5C
OP_NCALL2_ADDR_U16 = 0x5D
OP_CALL3_U16 = 0x5E
OP_NCALL3_ADDR_U16 = 0x5F

SIMPLE_OPS = {
    "lbyte": OP_LBYTE,
    "sbyte": OP_SBYTE,
    "lword": OP_LWORD,
    "sword": OP_SWORD,
    "add": 0x60,
    "sub": 0x61,
    "and": 0x62,
    "or": 0x63,
    "xor": 0x64,
    "shl": 0x65,
    "shr": 0x66,
    "neg": 0x67,
    "bnot": 0x68,
    "lnot": 0x69,
    "eq": 0x6A,
    "ne": 0x6B,
    "lt": 0x6C,
    "le": 0x6D,
    "gt": 0x6E,
    "ge": 0x6F,
    "mul": 0x70,
    "udiv": 0x71,
    "umod": 0x72,
    "sdiv": 0x73,
    "smod": 0x74,
}


class Insn:
    def __init__(self, op: str, args: list[str]) -> None:
        self.op = op
        self.args = args
        self.addr = 0
        self.size = 1


class EncodedPca:
    def __init__(
        self,
        entry: str,
        entry_defined: bool,
        bytecode: list[int | WordOperand],
        data: list[int],
        data_labels: dict[str, int],
        natives: list[str],
        externs: list[str],
        code_labels: dict[str, int],
        public_funcs: set[str],
        public_data: set[str],
    ) -> None:
        self.entry = entry
        self.entry_defined = entry_defined
        self.bytecode = bytecode
        self.data = data
        self.data_labels = data_labels
        self.natives = natives
        self.externs = externs
        self.code_labels = code_labels
        self.public_funcs = public_funcs
        self.public_data = public_data


class ObjectSymbolMap:
    def __init__(self) -> None:
        self.full_to_short: dict[str, str] = {}
        self.short_to_full: dict[str, str] = {}

    def map(self, symbol: str) -> str:
        if len(symbol) <= 15:
            return symbol
        if symbol in self.full_to_short:
            return self.full_to_short[symbol]

        raw = symbol[1:] if symbol.startswith("_") else symbol
        hval = 5381
        for ch in raw:
            hval = (((hval << 5) + hval) ^ ord(ch)) & 0xFFFF

        stem = raw[:8].ljust(8, "_")
        for seq in range(16):
            suffix = chr(ord("0") + seq) if seq < 10 else chr(ord("a") + seq - 10)
            short = f"_{stem}_{hval:04x}{suffix}"
            owner = self.short_to_full.get(short)
            if owner is None or owner == symbol:
                self.full_to_short[symbol] = short
                self.short_to_full[short] = symbol
                return short
        raise ValueError(f"object symbol short-name collision: {symbol}")


def shell_join(argv: list[str]) -> str:
    return " ".join(shlex.quote(arg) for arg in argv)


def decode_escapes(value: str, path: pathlib.Path, lineno: int) -> str:
    out: list[str] = []
    i = 0
    while i < len(value):
        ch = value[i]
        if ch != "\\":
            out.append(ch)
            i += 1
            continue
        i += 1
        if i >= len(value):
            raise ValueError(f"{path}:{lineno}: incomplete escape")
        esc = value[i]
        i += 1
        if esc == "n":
            out.append("\n")
        elif esc == "r":
            out.append("\r")
        elif esc == "t":
            out.append("\t")
        elif esc == "0":
            out.append("\0")
        elif esc == "\\":
            out.append("\\")
        elif esc == '"':
            out.append('"')
        elif esc == "x":
            if i + 2 > len(value):
                raise ValueError(f"{path}:{lineno}: incomplete hex escape")
            digits = value[i:i + 2]
            if not re.fullmatch(r"[0-9a-fA-F]{2}", digits):
                raise ValueError(f"{path}:{lineno}: invalid hex escape '\\x{digits}'")
            out.append(chr(int(digits, 16)))
            i += 2
        else:
            raise ValueError(f"{path}:{lineno}: unsupported escape '\\{esc}'")
    return "".join(out)


def escape_display(value: str) -> str:
    out: list[str] = []
    for ch in value:
        code = ord(ch)
        if ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\0":
            out.append("\\0")
        elif ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif code < 32 or code >= 127:
            out.append(f"\\x{code:02x}")
        else:
            out.append(ch)
    return "".join(out)


def load_expected(path: pathlib.Path) -> "OrderedDict[str, int]":
    expected: "OrderedDict[str, int]" = OrderedDict()
    for lineno, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) != 2:
            raise ValueError(f"{path}:{lineno}: expected '<test> <value>'")
        expected[parts[0]] = int(parts[1], 0)
    return expected


def load_text_manifest(path: pathlib.Path | None) -> "OrderedDict[str, str]":
    values: "OrderedDict[str, str]" = OrderedDict()
    if path is None or not path.exists():
        return values
    for lineno, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split(None, 1)
        name = parts[0]
        value = parts[1] if len(parts) == 2 else ""
        values[name] = decode_escapes(value, path, lineno)
    return values


def discover_tests(test_dir: pathlib.Path) -> dict[str, pathlib.Path]:
    return {
        path.stem: path
        for path in sorted(test_dir.glob("[0-9][0-9][0-9]_*.c"))
    }


def append_log(log_path: pathlib.Path, title: str, argv: list[str], proc: subprocess.CompletedProcess) -> None:
    with log_path.open("a") as log:
        log.write(f"== {title} ==\n")
        log.write(f"$ {shell_join(argv)}\n")
        log.write(f"exit={proc.returncode}\n")
        stdout = proc.stdout.decode("latin-1") if isinstance(proc.stdout, bytes) else (proc.stdout or "")
        stderr = proc.stderr.decode("latin-1") if isinstance(proc.stderr, bytes) else (proc.stderr or "")
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


def run_cmd(log_path: pathlib.Path, title: str, argv: list[str], binary: bool = False) -> subprocess.CompletedProcess:
    if binary:
        proc = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    else:
        proc = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=False)
    append_log(log_path, title, argv, proc)
    return proc


def parse_int(value: str) -> int:
    return int(value, 0)


def clean_line(line: str) -> str:
    return line.split(";", 1)[0].strip()


def insn_size(insn: Insn, labels: dict[str, int], pcode_symbols: set[str] | None = None) -> int:
    op = insn.op
    if op == "iconst":
        value = parse_int(insn.args[0])
        if value in (-1, 0, 1, 2):
            return 1
        if -128 <= value <= 127:
            return 2
        return 3
    if op in ("llocal", "slocal"):
        value = parse_int(insn.args[0])
        if 0 <= value <= 3:
            return 1
        if -128 <= value <= 127:
            return 2
        return 3
    if op == "addr_local":
        value = parse_int(insn.args[0])
        return 2 if -128 <= value <= 127 else 3
    if op in ("lglobal", "sglobal", "addr_global"):
        return 3
    if op == "addr_func":
        return 3
    if op in ("jmp", "jz", "jnz"):
        return insn.size
    if op == "call":
        argc = parse_int(insn.args[1])
        return 3 if 0 <= argc <= 3 else 4
    if op == "icall":
        return 2
    if op == "ncall":
        argc = parse_int(insn.args[1])
        pcode_targets = pcode_symbols if pcode_symbols is not None else set(labels.keys())
        if insn.args[0] in pcode_targets:
            return 3 if 0 <= argc <= 3 else 4
        return 3 if 0 <= argc <= 3 else 4
    if op in ("ret", "drop", "dup", "swap", "leave") or op in SIMPLE_OPS:
        return 1
    raise ValueError(f"unsupported p-code op for microemu: {op}")


def parse_pca(
    path: pathlib.Path,
    pcode_symbols: set[str] | None = None,
) -> tuple[str, list[Insn], dict[str, int], dict[str, int], list[int]]:
    entry = "_main"
    insns: list[Insn] = []
    labels: dict[str, int] = {}
    data_labels: dict[str, int] = {}
    data: list[int] = []
    for raw in path.read_text().splitlines():
        line = clean_line(raw)
        if not line:
            continue
        parts = line.split()
        op = parts[0]
        args = parts[1:]
        if op == "entry":
            entry = args[0]
        elif op in ("func", "static_func", "label"):
            labels[args[0]] = len(insns)
        elif op in ("data_label", "static_data_label"):
            data_labels[args[0]] = len(data)
        elif op == "data8":
            for value in args:
                data.append(parse_int(value) & 0xFF)
        elif op == "data16":
            for value in args:
                v = parse_int(value)
                data.append(v & 0xFF)
                data.append((v >> 8) & 0xFF)
        elif op == "zero":
            data.extend([0] * parse_int(args[0]))
        elif op == "end":
            break
        else:
            insns.append(Insn(op, args))

    for insn in insns:
        insn.size = 2 if insn.op in ("jmp", "jz", "jnz") else insn_size(insn, labels, pcode_symbols)
    for _ in range(8):
        pc = 0
        for insn in insns:
            insn.addr = pc
            pc += insn.size
        label_addr = {name: insns[index].addr if index < len(insns) else pc for name, index in labels.items()}
        changed = False
        for insn in insns:
            if insn.op in ("jmp", "jz", "jnz"):
                target = label_addr[insn.args[0]]
                rel = target - (insn.addr + 2)
                new_size = 2 if -128 <= rel <= 127 else 3
                if new_size != insn.size:
                    changed = True
                    insn.size = new_size
        if not changed:
            break
    pc = 0
    for insn in insns:
        insn.addr = pc
        pc += insn.size
    labels_addr = {name: insns[index].addr if index < len(insns) else pc for name, index in labels.items()}
    return entry, insns, labels_addr, data_labels, data


def emit_u16(out: list[int | WordOperand], value: int) -> None:
    out.append(value & 0xFF)
    out.append((value >> 8) & 0xFF)


def emit_word_symbol(out: list[int | WordOperand], symbol: str) -> None:
    out.append(("dw", symbol))


def bytecode_size(bytecode: list[int | WordOperand]) -> int:
    size = 0
    for item in bytecode:
        size += 2 if isinstance(item, tuple) else 1
    return size


def scan_pca_symbols(path: pathlib.Path) -> tuple[str, set[str], set[str]]:
    entry = "_main"
    public_funcs: set[str] = set()
    public_data: set[str] = set()
    for raw in path.read_text().splitlines():
        line = clean_line(raw)
        if not line:
            continue
        parts = line.split()
        op = parts[0]
        args = parts[1:]
        if op == "entry" and args:
            entry = args[0]
        elif op == "func" and args:
            public_funcs.add(args[0])
        elif op == "data_label" and args and not LOCAL_LABEL_RE.match(args[0]):
            public_data.add(args[0])
    return entry, public_funcs, public_data


def collect_public_pcode_symbols(paths: list[pathlib.Path]) -> tuple[set[str], set[str]]:
    funcs: set[str] = set()
    data: set[str] = set()
    for path in paths:
        _entry, module_funcs, module_data = scan_pca_symbols(path)
        funcs.update(module_funcs)
        data.update(module_data)
    return funcs, data


def encode_pca_object(path: pathlib.Path, pcode_symbols: set[str] | None = None) -> EncodedPca:
    entry, insns, labels, data_labels, data = parse_pca(path, pcode_symbols)
    if entry not in labels:
        entry_defined = False
    else:
        entry_defined = True
    _entry_name, public_funcs, public_data = scan_pca_symbols(path)
    out: list[int | WordOperand] = []
    native_ids: "OrderedDict[str, int]" = OrderedDict()
    externs: "OrderedDict[str, int]" = OrderedDict()
    pcode_targets = pcode_symbols if pcode_symbols is not None else set(labels.keys())
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
        elif op in ("llocal", "slocal"):
            value = parse_int(args[0])
            if op == "llocal" and 0 <= value <= 3:
                out.append(OP_LLOCAL_0 + value)
            elif op == "slocal" and 0 <= value <= 3:
                out.append(OP_SLOCAL_0 + value)
            elif -128 <= value <= 127:
                out.extend([OP_LLOCAL_S8 if op == "llocal" else OP_SLOCAL_S8, value & 0xFF])
            else:
                out.append(OP_LLOCAL_U16 if op == "llocal" else OP_SLOCAL_U16)
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
            target = args[0]
            if target not in labels and target not in pcode_targets:
                raise ValueError(f"unsupported native function pointer in p-code object: {target}")
            if target not in labels:
                externs[target] = 1
            emit_word_symbol(out, target)
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
            target = args[0]
            argc = parse_int(args[1])
            if 0 <= argc <= 2:
                out.append(OP_CALL0_U16 + argc)
                if target not in labels:
                    externs[target] = 1
                emit_word_symbol(out, target)
            elif argc == 3:
                out.append(OP_CALL3_U16)
                if target not in labels:
                    externs[target] = 1
                emit_word_symbol(out, target)
            else:
                out.append(OP_CALL_U16)
                if target not in labels:
                    externs[target] = 1
                emit_word_symbol(out, target)
                out.append(argc & 0xFF)
        elif op == "icall":
            out.extend([OP_ICALL_U8, parse_int(args[0]) & 0xFF])
        elif op == "ncall":
            native = args[0]
            argc = parse_int(args[1])
            if native in pcode_targets:
                if 0 <= argc <= 2:
                    out.append(OP_CALL0_U16 + argc)
                elif argc == 3:
                    out.append(OP_CALL3_U16)
                else:
                    out.append(OP_CALL_U16)
                if native not in labels:
                    externs[native] = 1
                emit_word_symbol(out, native)
                if argc > 3:
                    out.append(argc & 0xFF)
            else:
                if native not in native_ids:
                    native_ids[native] = len(native_ids)
                    externs[native] = 1
                if 0 <= argc <= 2:
                    out.append(OP_NCALL0_ADDR_U16 + argc)
                elif argc == 3:
                    out.append(OP_NCALL3_ADDR_U16)
                else:
                    out.extend([OP_NCALL_ADDR_U16, argc & 0xFF])
                emit_word_symbol(out, native)
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
            raise ValueError(f"unsupported p-code op for microemu: {op}")
    return EncodedPca(
        entry,
        entry_defined,
        out,
        data,
        data_labels,
        list(native_ids.keys()),
        list(externs.keys()),
        labels,
        public_funcs,
        public_data,
    )


def encode_pca(path: pathlib.Path) -> tuple[str, list[int | WordOperand], list[int], dict[str, int], list[str], list[str]]:
    encoded = encode_pca_object(path)
    if not encoded.entry_defined:
        raise ValueError(f"entry function not found: {encoded.entry}")
    return encoded.entry, encoded.bytecode, encoded.data, encoded.data_labels, encoded.natives, encoded.externs


def write_pcode_object_asm(
    path: pathlib.Path,
    entry: str,
    bytecode: list[int | WordOperand],
    data: list[int],
    data_labels: dict[str, int],
    natives: list[str],
    externs: list[str],
) -> None:
    encoded = EncodedPca(
        entry,
        True,
        bytecode,
        data,
        data_labels,
        natives,
        externs,
        {entry: 0},
        {entry},
        {label for label in data_labels if not LOCAL_LABEL_RE.match(label)},
    )
    write_encoded_pcode_object_asm(path, encoded, path.stem)


def safe_module_name(value: str) -> str:
    out: list[str] = []
    for ch in value:
        if ch.isalnum() or ch == "_":
            out.append(ch)
        else:
            out.append("_")
    text = "".join(out).strip("_")
    return text if text else "module"


def flush_db_chunk(lines: list[str], chunk: list[int]) -> None:
    if chunk:
        values = ", ".join(f"${value:02x}" for value in chunk)
        lines.append(f"\tdb\t{values}")
        chunk.clear()


def write_encoded_pcode_object_asm(
    path: pathlib.Path,
    encoded: EncodedPca,
    module_name: str,
    symbol_map: ObjectSymbolMap | None = None,
) -> None:
    prefix = "__pcd_" + safe_module_name(module_name)
    symbols = symbol_map if symbol_map is not None else ObjectSymbolMap()
    defined_symbols = set(encoded.code_labels.keys()) | set(encoded.data_labels.keys())
    object_symbols: dict[str, str] = {}
    for symbol in set(encoded.externs) | encoded.public_funcs | encoded.public_data:
        object_symbols[symbol] = symbols.map(symbol)

    def objname(symbol: str) -> str:
        return object_symbols.get(symbol, symbol)

    lines = [
        "; generated p-code object data",
    ]
    for symbol in encoded.externs:
        if symbol not in defined_symbols:
            lines.append(f"extern {objname(symbol)}")
    if encoded.entry_defined:
        lines.append("public __pcode_entry")
    for symbol in sorted(encoded.public_funcs):
        lines.append(f"public {objname(symbol)}")
    for symbol in sorted(encoded.public_data):
        lines.append(f"public {objname(symbol)}")
    lines.append("")
    if encoded.entry_defined:
        lines.extend([
            "__pcode_entry:",
            f"\tdw\t{encoded.entry}",
        ])
    lines.append(f"{prefix}_code_start:")
    labels_by_offset: dict[int, list[str]] = {}
    for label, offset in encoded.code_labels.items():
        labels_by_offset.setdefault(offset, []).append(label)
    chunk: list[int] = []
    offset = 0
    for item in encoded.bytecode:
        if offset in labels_by_offset:
            flush_db_chunk(lines, chunk)
            for label in labels_by_offset[offset]:
                lines.append(f"{objname(label)}:")
        if isinstance(item, tuple):
            flush_db_chunk(lines, chunk)
            lines.append(f"\tdw\t{objname(item[1])}")
            offset += 2
            continue
        chunk.append(item)
        offset += 1
        if len(chunk) == 16:
            flush_db_chunk(lines, chunk)
    flush_db_chunk(lines, chunk)
    if offset in labels_by_offset:
        for label in labels_by_offset[offset]:
            lines.append(f"{objname(label)}:")
    lines.append(f"{prefix}_code_end:")
    lines.append(f"{prefix}_data_start:")
    labels_by_offset: dict[int, list[str]] = {}
    for label, offset in encoded.data_labels.items():
        labels_by_offset.setdefault(offset, []).append(label)
    chunk = []
    for offset, value in enumerate(encoded.data):
        if offset in labels_by_offset:
            flush_db_chunk(lines, chunk)
            for label in labels_by_offset[offset]:
                lines.append(f"{objname(label)}:")
        chunk.append(value)
        if len(chunk) == 16:
            flush_db_chunk(lines, chunk)
    flush_db_chunk(lines, chunk)
    if len(encoded.data) in labels_by_offset:
        for label in labels_by_offset[len(encoded.data)]:
            lines.append(f"{objname(label)}:")
    lines.extend([f"{prefix}_data_end:", ""])
    path.write_text("\n".join(lines))


def compile_pcode(name: str, source: pathlib.Path, args: argparse.Namespace, log_path: pathlib.Path) -> tuple[bool, pathlib.Path, pathlib.Path]:
    i_path = args.build_dir / f"{name}.i"
    pca_path = args.build_dir / f"{name}.pca"
    argv = [str(args.preprocessor), "-o", str(i_path)]
    for include_dir in args.include_dir:
        argv.extend(["-I", str(include_dir)])
    argv.append(str(source))
    proc = run_cmd(log_path, "preprocess", argv)
    if proc.returncode != 0:
        return False, i_path, pca_path
    argv = [str(args.cc_only), "--backend", "pcode", "-o", str(pca_path), str(i_path)]
    proc = run_cmd(log_path, "compile-pcode", argv)
    if proc.returncode == 0 and getattr(args, "pcode_opt", False):
        import pcode_opt

        raw_path = args.build_dir / f"{name}.raw.pca"
        pca_path.replace(raw_path)
        stats = pcode_opt.optimize_pca_file(raw_path, pca_path)
        with log_path.open("a") as log:
            log.write("== pcode-opt ==\n")
            log.write(f"removed_temp_roundtrips={stats['removed_temp_roundtrips']}\n")
            log.write(f"rewritten_store_load_roundtrips={stats['rewritten_store_load_roundtrips']}\n")
            log.write(f"rewrite_byte_savings={stats['rewrite_byte_savings']}\n")
            log.write(f"const_branch_to_jump={stats['const_branch_to_jump']}\n")
            log.write(f"const_branch_removed={stats['const_branch_removed']}\n")
            log.write(f"jump_to_next_removed={stats['jump_to_next_removed']}\n")
            log.write(f"cond_to_next_replaced={stats['cond_to_next_replaced']}\n")
            log.write(f"inverted_branch_jumps={stats['inverted_branch_jumps']}\n")
            log.write(f"branch_threaded={stats['branch_threaded']}\n")
            log.write(f"branch_thread_byte_savings={stats['branch_thread_byte_savings']}\n")
            log.write(f"bytecode_before={stats['bytecode_before']}\n")
            log.write(f"bytecode_after={stats['bytecode_after']}\n")
            log.write(f"bytecode_saved={stats['bytecode_saved']}\n\n")
    return proc.returncode == 0, i_path, pca_path


def compile_native_size(name: str, i_path: pathlib.Path, args: argparse.Namespace, log_path: pathlib.Path) -> tuple[int | None, int | None, int | None]:
    asm_path = args.build_dir / f"{name}.native.asm"
    bin_path = args.build_dir / f"{name}.native.bin"
    argv = [str(args.cc_only), "--backend", "microcpu", "-o", str(asm_path), str(i_path)]
    proc = run_cmd(log_path, "compile-native-size", argv)
    if proc.returncode != 0:
        return None, None, None
    asm_bytes = asm_path.stat().st_size
    asm_lines = len(asm_path.read_text(errors="replace").splitlines())
    argv = [str(args.assembler), "-binary", str(asm_path), str(bin_path)]
    proc = run_cmd(log_path, "assemble-native-size", argv)
    if proc.returncode == 0:
        return asm_bytes, asm_lines, bin_path.stat().st_size
    return asm_bytes, asm_lines, None


def assemble(args: argparse.Namespace, source: pathlib.Path, obj: pathlib.Path, log_path: pathlib.Path) -> bool:
    argv = [str(args.assembler), "-object", str(source), str(obj)]
    proc = run_cmd(log_path, "assemble", argv)
    return proc.returncode == 0


def link(args: argparse.Namespace, objects: list[pathlib.Path], bin_path: pathlib.Path, log_path: pathlib.Path) -> bool:
    argv = [str(args.linker), "-binary", "-o", str(bin_path)]
    argv.extend(str(obj) for obj in objects)
    proc = run_cmd(log_path, "link", argv)
    return proc.returncode == 0


def run_microemu(args: argparse.Namespace, bin_path: pathlib.Path, log_path: pathlib.Path, expect_uart: bool) -> tuple[bool, int | None, str, str]:
    argv = [
        str(args.emulator),
        "--board", args.board,
        "--format", "bin",
        "--load-addr", "0",
        "--max-steps", str(args.max_steps),
        "--stop-on-self-branch",
        "--dump-regs",
        "--stats",
    ]
    if not expect_uart:
        argv.append("--quiet-uart")
    argv.append(str(bin_path))
    proc = run_cmd(log_path, "microemu", argv, binary=True)
    stdout = proc.stdout.decode("latin-1") if isinstance(proc.stdout, bytes) else (proc.stdout or "")
    stderr = proc.stderr.decode("latin-1") if isinstance(proc.stderr, bytes) else (proc.stderr or "")
    output = stdout + stderr
    if "stopped on self-branch" not in output:
        return False, None, "emulator did not reach self-branch halt", stdout
    matches = REG_RE.findall(output)
    if proc.returncode != 0 or not matches:
        return False, None, "emulator failed before final V0 could be parsed", stdout
    return True, int(matches[-1], 16), "", stdout


def run_one(
    name: str,
    source: pathlib.Path,
    expected: int,
    expected_uart: str | None,
    args: argparse.Namespace,
    interp_obj: pathlib.Path,
    runtime_obj: pathlib.Path,
    rows: list[str],
) -> bool:
    log_path = args.build_dir / f"{name}.microemu.log"
    pcode_asm = args.build_dir / f"{name}.pcode.asm"
    pcode_obj = args.build_dir / f"{name}.pcode.o"
    bin_path = args.build_dir / f"{name}.bin"
    log_path.write_text("")

    print(f"{name}:")
    ok, i_path, pca_path = compile_pcode(name, source, args, log_path)
    if ok:
        print("  PCODE COMPILE PASS")
    else:
        print("  PCODE COMPILE FAIL")
        print(f"  log: {log_path}")
        return False
    native_asm_bytes, native_asm_lines, native_bin_bytes = compile_native_size(name, i_path, args, log_path)
    try:
        encoded = encode_pca_object(pca_path)
        if not encoded.entry_defined:
            raise ValueError(f"entry function not found: {encoded.entry}")
        write_encoded_pcode_object_asm(pcode_asm, encoded, name)
    except Exception as exc:
        print(f"  PCODE OBJECT FAIL {exc}")
        print(f"  log: {log_path}")
        with log_path.open("a") as log:
            log.write(f"pcode object error: {exc}\n")
        return False
    if assemble(args, pcode_asm, pcode_obj, log_path):
        print("  PCODE ASSEMBLE PASS")
    else:
        print("  PCODE ASSEMBLE FAIL")
        print(f"  log: {log_path}")
        return False
    objects = [interp_obj]
    if encoded.natives:
        objects.append(runtime_obj)
    objects.append(pcode_obj)
    if link(args, objects, bin_path, log_path):
        print("  LINK PASS")
    else:
        print("  LINK FAIL")
        print(f"  log: {log_path}")
        return False
    run_ok, actual, reason, actual_uart = run_microemu(args, bin_path, log_path, expected_uart is not None)
    if not run_ok:
        print(f"  RUN FAIL {reason}")
        print(f"  log: {log_path}")
        return False
    if actual != (expected & 0xFFFF):
        print(f"  RUN FAIL expected={expected} actual={actual}")
        print(f"  log: {log_path}")
        return False
    print(f"  RUN PASS expected={expected} actual={actual}")
    if expected_uart is not None:
        if actual_uart != expected_uart:
            print(
                "  UART FAIL "
                f"expected={escape_display(expected_uart)} "
                f"actual={escape_display(actual_uart)}"
            )
            print(f"  log: {log_path}")
            return False
        print(
            "  UART PASS "
            f"expected={escape_display(expected_uart)} "
            f"actual={escape_display(actual_uart)}"
            )
    rows.append(f"{name}:")
    rows.append(f"  p-code bytecode bytes: {bytecode_size(encoded.bytecode)}")
    rows.append(f"  p-code global data bytes: {len(encoded.data)}")
    rows.append("  p-code native table bytes: 0")
    rows.append(f"  p-code native call symbols: {len(encoded.natives)}")
    rows.append(f"  pcode.o size: {pcode_obj.stat().st_size}")
    rows.append(f"  pcode_interpreter.o size: {interp_obj.stat().st_size}")
    if encoded.natives:
        rows.append(f"  runtime_object.o size: {runtime_obj.stat().st_size}")
    rows.append(f"  linked p-code binary bytes: {bin_path.stat().st_size}")
    if native_asm_bytes is not None:
        rows.append(f"  native asm bytes: {native_asm_bytes}")
        rows.append(f"  native asm lines: {native_asm_lines}")
    if native_bin_bytes is not None:
        rows.append(f"  native backend binary bytes: {native_bin_bytes}")
    else:
        rows.append("  native backend binary bytes: unavailable")
    return True


def normalize_test_name(name: str) -> str:
    path = pathlib.Path(name)
    if path.suffix == ".c":
        return path.stem
    return path.name


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected", required=True, type=pathlib.Path)
    parser.add_argument("--expected-uart", type=pathlib.Path)
    parser.add_argument("--preprocessor", required=True, type=pathlib.Path)
    parser.add_argument("--cc-only", required=True, type=pathlib.Path)
    parser.add_argument("--assembler", required=True, type=pathlib.Path)
    parser.add_argument("--linker", required=True, type=pathlib.Path)
    parser.add_argument("--emulator", required=True, type=pathlib.Path)
    parser.add_argument("--runtime-dir", required=True, type=pathlib.Path)
    parser.add_argument("--build-dir", default=pathlib.Path("build/pcode-microemu"), type=pathlib.Path)
    parser.add_argument("--include-dir", action="append", default=[], type=pathlib.Path)
    parser.add_argument("--board", default="hc1200-mcu")
    parser.add_argument("--max-steps", default=1_000_000, type=int)
    parser.add_argument("--pcode-opt", action="store_true")
    parser.add_argument("--test")
    args = parser.parse_args()

    expected = load_expected(args.expected)
    expected_uart = load_text_manifest(args.expected_uart)
    tests = discover_tests(args.expected.parent)
    selected = list(expected.keys())
    if args.test:
        name = normalize_test_name(args.test)
        if name not in expected:
            print(f"FAIL: unknown test {args.test}", file=sys.stderr)
            return 1
        selected = [name]
    args.build_dir.mkdir(parents=True, exist_ok=True)
    interp_obj = args.build_dir / "pcode_interpreter.o"
    interp_log = args.build_dir / "pcode_interpreter.log"
    interp_log.write_text("")
    if not assemble(args, args.runtime_dir / "pcode_interpreter.asm", interp_obj, interp_log):
        print(f"FAIL: p-code interpreter assembly failed: {interp_log}", file=sys.stderr)
        return 1
    runtime_obj = args.build_dir / "runtime_object.o"
    runtime_log = args.build_dir / "runtime_object.log"
    runtime_log.write_text("")
    if not assemble(args, args.runtime_dir / "runtime_object.asm", runtime_obj, runtime_log):
        print(f"FAIL: p-code native runtime assembly failed: {runtime_log}", file=sys.stderr)
        return 1

    rows = ["Microcpu p-code size report", ""]
    ok = True
    for name in selected:
        if name not in tests:
            print(f"FAIL: missing pcode-tests/{name}.c", file=sys.stderr)
            ok = False
            continue
        ok = run_one(name, tests[name], expected[name], expected_uart.get(name), args, interp_obj, runtime_obj, rows) and ok
    (args.build_dir / "size-report.txt").write_text("\n".join(rows) + "\n")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

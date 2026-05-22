#!/usr/bin/env python3
"""Helpers for merging multiple textual p-code modules."""

from __future__ import annotations

import pathlib
import re
from dataclasses import dataclass, field

import run_pcode_microemu as pcode


LOCAL_LABEL_RE = re.compile(r"^L[0-9]+$")


@dataclass
class Module:
    name: str
    path: pathlib.Path
    lines: list[tuple[str, list[str]]] = field(default_factory=list)
    local_map: dict[str, str] = field(default_factory=dict)
    public_funcs: set[str] = field(default_factory=set)
    public_data: set[str] = field(default_factory=set)


def _prefixed(index: int, name: str) -> str:
    clean = name[1:] if name.startswith("_") else name
    return f"__p{index}_{clean}"


def _read_module(index: int, path: pathlib.Path) -> Module:
    module = Module(path.stem, path)
    for raw in path.read_text().splitlines():
        line = pcode.clean_line(raw)
        if not line:
            continue
        parts = line.split()
        op = parts[0]
        args = parts[1:]
        if op in ("entry", "end"):
            continue
        module.lines.append((op, args))
        if not args:
            continue
        name = args[0]
        if op in ("static_func", "static_data_label"):
            module.local_map[name] = _prefixed(index, name)
        elif op in ("func", "data_label", "label") and LOCAL_LABEL_RE.match(name):
            module.local_map[name] = _prefixed(index, name)
        elif op == "func":
            module.public_funcs.add(name)
        elif op == "data_label":
            module.public_data.add(name)
    return module


def _rename(module: Module, name: str) -> str:
    return module.local_map.get(name, name)


def _emit_line(out: list[str], op: str, args: list[str]) -> None:
    if args:
        out.append(" ".join([op] + args))
    else:
        out.append(op)


def merge_pca_files(paths: list[pathlib.Path], output: pathlib.Path, entry: str = "_main") -> None:
    modules = [_read_module(index, path) for index, path in enumerate(paths)]
    public_funcs: set[str] = set()
    public_data: set[str] = set()
    for module in modules:
        public_funcs.update(module.public_funcs)
        public_data.update(module.public_data)

    out: list[str] = [
        "; merged p-code assembly",
        f"entry {entry}",
    ]
    for module in modules:
        out.append(f"; module {module.name}")
        for op, args in module.lines:
            args = list(args)
            if op == "static_func":
                _emit_line(out, "func", [_rename(module, args[0])])
            elif op == "static_data_label":
                _emit_line(out, "data_label", [_rename(module, args[0])])
            elif op in ("func", "data_label", "label"):
                _emit_line(out, op, [_rename(module, args[0])])
            elif op in ("jmp", "jz", "jnz"):
                _emit_line(out, op, [_rename(module, args[0])])
            elif op == "call":
                args[0] = _rename(module, args[0])
                _emit_line(out, op, args)
            elif op == "ncall":
                target = _rename(module, args[0])
                if target in public_funcs or target != args[0]:
                    _emit_line(out, "call", [target, args[1]])
                else:
                    _emit_line(out, op, args)
            elif op == "addr_func":
                target = _rename(module, args[0])
                if target not in public_funcs and target == args[0]:
                    raise ValueError(f"unsupported native function pointer in p-code module: {target}")
                _emit_line(out, op, [target])
            elif op in ("lglobal", "sglobal", "addr_global"):
                target = _rename(module, args[0])
                _emit_line(out, op, [target])
            else:
                _emit_line(out, op, args)
    out.append("end")
    output.write_text("\n".join(out) + "\n")

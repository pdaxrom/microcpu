"""Reassemble upstream J-11 cases and replay each step on the microengine."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


def checked(command, **kwargs):
    result = subprocess.run(command, text=True, capture_output=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f"{' '.join(map(str, command))}\n{result.stdout}{result.stderr}")
    return result


def sparse_memory(pairs):
    result = bytearray(65536)
    for address, value in pairs:
        result[address] = value
    return result


def write_bytes(path, memory):
    path.write_text("\n".join(f"{value:02x}" for value in memory) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asm11", required=True)
    parser.add_argument("--vvp", default="vvp")
    parser.add_argument("--testbench", default="build/tb_j11_core_reference.vvp")
    parser.add_argument("--banks", action="store_true")
    args = parser.parse_args()
    directory = Path("build/core_reference")
    directory.mkdir(parents=True, exist_ok=True)
    command = ["build/core_reference_export"] + (["--banks"] if args.banks else [])
    result = checked(command)
    (directory / "vectors.jsonl").write_text(result.stdout)
    print(result.stderr.strip(), flush=True)
    cases = [json.loads(line) for line in result.stdout.splitlines()]
    if not cases:
        raise RuntimeError("Reference exported no cases")

    listing = Path("build/j11_ucode.lst").read_text()
    labels = {}
    for name in ("fetch_instruction", "wait_instruction"):
        matches = re.findall(rf"^\[{name}\]\s+([0-9A-Fa-f]+)$", listing, re.M)
        if len(matches) != 1:
            raise RuntimeError(f"Cannot locate microcode label {name}: {matches}")
        labels[name] = int(matches[0], 16)

    failures = []
    eis = 0
    for index, case in enumerate(cases):
        stem = directory / f"{index:03d}_{case['name']}"
        source = stem.with_suffix(".asm")
        binary = stem.with_suffix(".bin")
        before = sparse_memory(case["memory_before"])
        instruction = case["asm"]
        if case["name"] in {"jmp_mode0_trap_DCJ11", "jsr_mode0_trap_DCJ11"}:
            opcode = int.from_bytes(before[case["pc"]:case["pc"] + 2], "little")
            instruction = f"dw 0{opcode:o}\t; intentionally illegal: {instruction}"
        source.write_text(f"; From tests/core_tests.c: {case['name']}\n"
                          f"\tcpu dcj-11\n\torg 0{case['pc']:o}\n\t{instruction}\n")
        checked([args.asm11, "-binary", "--cpu", "dcj-11", str(source), str(binary)])
        expected = sparse_memory(case["memory_after"])
        assembled = binary.read_bytes()
        pc, length = case["pc"], case["length"]
        # Binary output starts at the first ORG, without leading padding.
        encoded = assembled
        if len(assembled) != length or encoded != before[pc:pc + length]:
            raise RuntimeError(f"{source}: assembler round-trip differs from core test")
        before[pc:pc + length] = encoded
        write_bytes(directory / "input.hex", before)
        write_bytes(directory / "expected.hex", expected)
        state = (case["before"] + case["after"] + case["banks_before"] +
                 case["banks_after"] + [case["wait_before"], case["wait_after"]] +
                 case["cpu_io_before"] + case["cpu_io_after"] +
                 case["inactive_before"] + case["inactive_after"] +
                 [case["regset_valid"]])
        (directory / "state.hex").write_text("\n".join(f"{value:04x}" for value in state) + "\n")
        cmd = [args.vvp, args.testbench,
               f"+FETCH_PC={labels['fetch_instruction']:x}",
               f"+WAIT_PC={labels['wait_instruction']:x}",
               f"+CHECK_BANKS={int(args.banks and bool(case['banks_valid']))}"]
        replay = subprocess.run(cmd, text=True, capture_output=True, timeout=30)
        if replay.returncode:
            failures.append(case["name"])
            print(f"FAIL: {index:03d} {case['name']} ({case['asm']})\n"
                  f"{replay.stdout}{replay.stderr}", flush=True)
            # Keep inputs and expected state for every failed case.
            for suffix in ("input.hex", "expected.hex", "state.hex"):
                stem.with_suffix("." + suffix).write_bytes((directory / suffix).read_bytes())
        if case["asm"].split()[0] in {"MUL", "DIV", "ASH", "ASHC"}:
            eis += 1
        if (index + 1) % 50 == 0:
            print(f"Checked {index + 1}/{len(cases)} J-11 instruction snapshots", flush=True)
    print(f"J-11 no-MMU RTL: {len(cases) - len(failures)}/{len(cases)} passed; "
          f"{eis} EIS cases; {len(failures)} failed")
    return bool(failures)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError, ValueError) as exc:
        sys.exit(str(exc))

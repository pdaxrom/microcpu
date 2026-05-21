#!/usr/bin/env python3
"""Rewrite the first assembler ORG directive in a source copy."""

import argparse
import re
from pathlib import Path


ORG_RE = re.compile(r"^(\s*)org\s+(\$[0-9a-fA-F]+|0x[0-9a-fA-F]+|\d+)\s*$", re.IGNORECASE)


def parse_addr(text):
    if text.startswith("$"):
        value = int(text[1:], 16)
    else:
        value = int(text, 0)
    if value < 0 or value > 0xffff:
        raise argparse.ArgumentTypeError("address must fit into 16 bits")
    return value


def main():
    parser = argparse.ArgumentParser(
        description="Copy a microcpu assembly source and replace its first ORG directive."
    )
    parser.add_argument("--org", required=True, type=parse_addr,
        help="new origin address, for example 0x0800 or $0800")
    parser.add_argument("input", type=Path, help="input .asm source")
    parser.add_argument("output", type=Path, help="output .asm source")
    args = parser.parse_args()

    lines = args.input.read_text().splitlines(keepends=True)
    replaced = False
    for i, line in enumerate(lines):
        match = ORG_RE.match(line.rstrip("\r\n"))
        if match:
            newline = "\n" if line.endswith("\n") else ""
            lines[i] = f"{match.group(1)}org\t${args.org:04x}{newline}"
            replaced = True
            break

    if not replaced:
        raise SystemExit(f"{args.input}: ORG directive not found")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("".join(lines))


if __name__ == "__main__":
    main()

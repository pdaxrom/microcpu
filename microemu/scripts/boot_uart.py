#!/usr/bin/env python3
"""Build a UART RX byte stream for the microcomp bootloader."""

import argparse
import re
import sys
from pathlib import Path


PACKET_SIZE = 14


def parse_u16(text):
    if text.startswith("$"):
        value = int(text[1:], 16)
    else:
        value = int(text, 0)
    if value < 0 or value > 0xffff:
        raise argparse.ArgumentTypeError("address must fit into 16 bits")
    return value


def append_word(out, value):
    out.append((value >> 8) & 0xff)
    out.append(value & 0xff)


def decode_escaped_text(text):
    out = bytearray()
    i = 0
    while i < len(text):
        ch = text[i]
        if ch != "\\":
            code = ord(ch)
            if code > 0xff:
                raise ValueError("text contains a character outside byte range")
            out.append(code)
            i += 1
            continue

        i += 1
        if i >= len(text):
            raise ValueError("trailing backslash in escaped text")
        esc = text[i]
        i += 1
        if esc == "n":
            out.append(10)
        elif esc == "r":
            out.append(13)
        elif esc == "t":
            out.append(9)
        elif esc == "0":
            out.append(0)
        elif esc == "\\":
            out.append(ord("\\"))
        elif esc == "x":
            if i + 2 > len(text):
                raise ValueError("incomplete \\xHH escape")
            out.append(int(text[i:i + 2], 16))
            i += 2
        else:
            raise ValueError(f"unsupported escape \\{esc}")
    return bytes(out)


def parse_hex_bytes(text):
    tokens = [token for token in re.split(r"[\s,]+", text.strip()) if token]
    out = bytearray()
    if len(tokens) == 1 and len(tokens[0]) > 2:
        hex_digits = tokens[0]
        if len(hex_digits) % 2 != 0:
            raise ValueError("hex string without separators needs even length")
        tokens = [hex_digits[i:i + 2] for i in range(0, len(hex_digits), 2)]
    for token in tokens:
        value = int(token, 16)
        if value < 0 or value > 0xff:
            raise ValueError(f"hex byte out of range: {token}")
        out.append(value)
    return bytes(out)


def build_stream(payload, start, go_addr, sync, append_bytes):
    end = start + len(payload)
    if end > 0x10000:
        raise ValueError(f"image does not fit: start=${start:04x}, size={len(payload)}")

    out = bytearray()
    if sync:
        out.append(ord("z"))

    out.append(ord("L"))
    append_word(out, start)
    append_word(out, end)

    for offset in range(0, len(payload), PACKET_SIZE):
        packet = payload[offset:offset + PACKET_SIZE]
        out += packet
        out += bytes(PACKET_SIZE - len(packet))

    if go_addr is not None:
        out.append(ord("G"))
        append_word(out, go_addr)

    out += append_bytes
    return bytes(out), end


def main():
    parser = argparse.ArgumentParser(
        description="Generate bytes for bootldr.asm UART load/go commands."
    )
    parser.add_argument("image", type=Path, help="binary image to load")
    parser.add_argument("--start", default=0x0800, type=parse_u16,
        help="load start address, default: 0x0800")
    parser.add_argument("--go", type=parse_u16,
        help="execution address, default: same as --start")
    parser.add_argument("--no-go", action="store_true",
        help="do not append a G command after loading")
    parser.add_argument("--no-sync", action="store_true",
        help="do not prepend the startup z byte")
    parser.add_argument("--append-text", default="",
        help=r"append escaped text after G, for example '1.5 2 *\nq'")
    parser.add_argument("--append-hex", default="",
        help="append hex bytes after G, separated by spaces or commas")
    parser.add_argument("-o", "--output", type=Path,
        help="output file; defaults to stdout")
    parser.add_argument("--verbose", action="store_true",
        help="print stream details to stderr")
    args = parser.parse_args()

    if args.go is not None and args.no_go:
        parser.error("--go and --no-go cannot be used together")

    payload = args.image.read_bytes()
    go_addr = None if args.no_go else (args.go if args.go is not None else args.start)
    try:
        append_bytes = decode_escaped_text(args.append_text)
        if args.append_hex:
            append_bytes += parse_hex_bytes(args.append_hex)
        stream, end = build_stream(payload, args.start, go_addr,
            not args.no_sync, append_bytes)
    except ValueError as exc:
        parser.error(str(exc))

    if args.output is None:
        sys.stdout.buffer.write(stream)
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(stream)

    if args.verbose:
        go_text = "none" if go_addr is None else f"${go_addr:04x}"
        print(
            f"start=${args.start:04x} end=${end:04x} "
            f"payload={len(payload)} stream={len(stream)} go={go_text}",
            file=sys.stderr,
        )


if __name__ == "__main__":
    main()

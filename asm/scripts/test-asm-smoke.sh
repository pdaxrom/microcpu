#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ASM_DIR="$ROOT_DIR/tests/asm-smoke"
OUT_DIR="$ASM_DIR/out"
BIN="$ROOT_DIR/microasm"

if [ ! -x "$BIN" ] || [ "$ROOT_DIR/microasm.c" -nt "$BIN" ]; then
    cc -Wall -Wpedantic -g -o "$BIN" "$ROOT_DIR/microasm.c"
fi

mkdir -p "$OUT_DIR"

failures=""
total=0

for asm in "$ASM_DIR"/*.asm; do
    [ -e "$asm" ] || continue
    total=$((total + 1))
    base=$(basename "$asm" .asm)
    out="$OUT_DIR/$base.mem"
    if "$BIN" "$asm" "$out" >"$OUT_DIR/$base.log" 2>&1; then
        :
    else
        failures="$failures $base.asm"
    fi
done

total=$((total + 1))
cli_out="$OUT_DIR/group-conditional-cli-define.mem"
cli_expected="$OUT_DIR/group-conditional-cli-define.expected"
printf '0000: 11 22\n' >"$cli_expected"
if "$BIN" -DCLI_FEATURE -DCLI_VALUE='$22' -DCLI_REMOVED -UCLI_REMOVED \
        "$ASM_DIR/group-conditional-cli.asm" "$cli_out" \
        >"$OUT_DIR/group-conditional-cli-define.log" 2>&1 &&
        cmp -s "$cli_expected" "$cli_out"; then
    :
else
    failures="$failures group-conditional-cli.define"
fi

if [ -n "$failures" ]; then
    echo "asm-smoke: failed:$failures"
    exit 1
fi

echo "asm-smoke: passed $total"

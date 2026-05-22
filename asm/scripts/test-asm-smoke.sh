#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ASM_DIR="$ROOT_DIR/tests/asm-smoke"
OUT_DIR="$ASM_DIR/out"
BIN="$ROOT_DIR/microasm"
LINK="$ROOT_DIR/microlink"
DIS="$ROOT_DIR/microdis"

if [ ! -x "$BIN" ] || [ "$ROOT_DIR/microasm.c" -nt "$BIN" ]; then
    cc -Wall -Wpedantic -g -o "$BIN" "$ROOT_DIR/microasm.c"
fi
if [ ! -x "$LINK" ] || [ "$ROOT_DIR/microlink.c" -nt "$LINK" ]; then
    cc -Wall -Wpedantic -g -o "$LINK" "$ROOT_DIR/microlink.c"
fi
if [ ! -x "$DIS" ] || [ "$ROOT_DIR/microdis.c" -nt "$DIS" ]; then
    cc -Wall -Wpedantic -g -o "$DIS" "$ROOT_DIR/microdis.c"
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

total=$((total + 1))
obj_main="$OUT_DIR/object-main.obj"
obj_lib="$OUT_DIR/object-lib.obj"
obj_out="$OUT_DIR/object-linked.mem"
obj_expected="$OUT_DIR/object-linked.expected"
obj_symbols="$OUT_DIR/object-symbols.txt"
obj_symbols_expected="$OUT_DIR/object-symbols.expected"
obj_dis="$OUT_DIR/object-main.dis"
obj_dis_expected="$OUT_DIR/object-main.dis.expected"
printf '0100: 08 01 09 01 43 09 53 01 CC AA BB\n' >"$obj_expected"
printf 'Symbols:\n0100 start\n0109 ext_target\n' >"$obj_symbols_expected"
cat >"$obj_dis_expected" <<'EOF'
; object file
extern ext_target
public start
; entry $0000

start:
0000: 0800    eq pc, pc ; reloc word code_base
0002: 0000    ldrl pc, pc, pc ; reloc word ext_target
0004: 4300    setl v0, $00 ; reloc lsb ext_target
0006: 5300    seth v0, $00 ; reloc msb ext_target
0008: CC      db $CC
EOF
if "$BIN" -object "$ASM_DIR/object/main.asm" "$obj_main" \
        >"$OUT_DIR/object-main.log" 2>&1 &&
        "$BIN" -object "$ASM_DIR/object/lib.asm" "$obj_lib" \
        >"$OUT_DIR/object-lib.log" 2>&1 &&
        "$LINK" -symbols -org '$100' -o "$obj_out" "$obj_main" "$obj_lib" \
        >"$obj_symbols" 2>"$OUT_DIR/object-linked.log" &&
        cmp -s "$obj_expected" "$obj_out" &&
        cmp -s "$obj_symbols_expected" "$obj_symbols" &&
        "$DIS" -object "$obj_main" >"$obj_dis" &&
        cmp -s "$obj_dis_expected" "$obj_dis"; then
    :
else
    failures="$failures object-link"
fi

total=$((total + 1))
dis_bin="$OUT_DIR/disasm.bin"
dis_out="$OUT_DIR/disasm-binary.dis"
dis_expected="$OUT_DIR/disasm-binary.expected"
printf '\103\022\123\064\260\001' >"$dis_bin"
cat >"$dis_expected" <<'EOF'
0100: 4312    setl v0, $12
0102: 5334    seth v0, $34
0104: B001    b $0106
EOF
if "$DIS" -binary -org '$100' "$dis_bin" >"$dis_out" &&
        cmp -s "$dis_expected" "$dis_out"; then
    :
else
    failures="$failures microdis-binary"
fi

if [ -n "$failures" ]; then
    echo "asm-smoke: failed:$failures"
    exit 1
fi

echo "asm-smoke: passed $total"

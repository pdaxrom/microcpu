HOSTCC ?= cc
PYTHON ?= python3
ASM ?= ../asm/microasm
EMU ?= ../microemu/microemu

BUILD := build
CC_BIN := $(BUILD)/scc-microcpu

HOST_CFLAGS := -std=gnu89 -fsigned-char -DTARGET_MICROCPU -Wall \
	-Wno-implicit-int -Wno-implicit-function-declaration \
	-Wno-int-conversion -Wno-incompatible-pointer-types \
	-Wno-return-type -Wno-parentheses -Wno-pointer-sign \
	-Wno-unused-value -Wno-unused-variable -Wno-format \
	-Wno-deprecated-non-prototype -Wno-pointer-integer-compare \
	-Wno-compare-distinct-pointer-types -Wno-empty-body

SRCS := \
	src/cc1.c \
	src/cc2.c \
	src/cc3.c \
	src/cc4.c \
	src/codegen_microcpu.c \
	src/host_compat.c

TEST_SRCS := $(sort $(wildcard tests/[0-9][0-9][0-9]_*.c))
TEST_ASMS := $(patsubst tests/%.c,$(BUILD)/%.asm,$(TEST_SRCS))
TEST_BINS := $(patsubst tests/%.c,$(BUILD)/%.bin,$(TEST_SRCS))

.PHONY: all test assemble run clean

all: $(CC_BIN)

test: $(TEST_BINS)
	$(PYTHON) tests/run_tests.py --emulator $(EMU) $(TEST_BINS)

assemble: $(TEST_BINS)

run: test

$(BUILD):
	mkdir -p $(BUILD)

$(CC_BIN): $(SRCS) src/cc.h src/notice.h src/host_compat.h src/smallc_proto.h | $(BUILD)
	$(HOSTCC) $(HOST_CFLAGS) -o $@ $(SRCS)

$(BUILD)/%.asm: tests/%.c $(CC_BIN) | $(BUILD)
	$(CC_BIN) $< > $@

$(BUILD)/%.bin: $(BUILD)/%.asm runtime/microcpu_cc.inc runtime/lib16.asm runtime/string.asm
	$(ASM) -binary $< $@ > $@.log 2>&1 || { cat $@.log; exit 1; }

clean:
	rm -rf $(BUILD)

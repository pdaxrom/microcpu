HOSTCC ?= cc
PYTHON ?= python3
ASM ?= ../asm/microasm
EMU ?= ../microemu/microemu
EMU_BOARD ?= hc1200-mcu
MAX_STEPS ?= 1000000
TRACE ?= 0

BUILD := build
TEST_BUILD := $(BUILD)/tests
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

TRACE_ARG := $(if $(filter 1,$(TRACE)),--trace,)
TEST_ARG := $(if $(TEST),--test $(TEST),)
TEST_RUNNER_ARGS := --expected tests/expected.txt \
	--expected-uart tests/expected_uart.txt \
	--input-uart tests/input_uart.txt --compiler $(CC_BIN) \
	--assembler $(ASM) --emulator $(EMU) --board $(EMU_BOARD) \
	--max-steps $(MAX_STEPS) --build-dir $(TEST_BUILD)

.PHONY: all test assemble run clean

all: $(CC_BIN)

test: $(CC_BIN)
	$(PYTHON) tests/run_tests.py $(TEST_RUNNER_ARGS) $(TRACE_ARG) $(TEST_ARG)

assemble: test

run: test

$(BUILD):
	mkdir -p $(BUILD)

$(CC_BIN): $(SRCS) src/cc.h src/notice.h src/host_compat.h src/smallc_proto.h | $(BUILD)
	$(HOSTCC) $(HOST_CFLAGS) -o $@ $(SRCS)

clean:
	rm -rf $(BUILD)

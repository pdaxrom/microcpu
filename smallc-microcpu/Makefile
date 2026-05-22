HOSTCC ?= cc
PYTHON ?= python3
ASM ?= ../asm/microasm
LD = ../asm/microlink
EMU ?= ../microemu/microemu
EMU_BOARD ?= hc1200-mcu
MAX_STEPS ?= 1000000
TRACE ?= 0
SELFHOST_TIMEOUT ?= 3
OBJECT_MODE ?= 0

BUILD := build
TEST_BUILD := $(BUILD)/tests
MULTI_TEST_BUILD := $(BUILD)/tests-multi
SELFHOST_BUILD := $(BUILD)/selfhost-smoke
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

SELFHOST_SRCS := \
	src/cc1.c \
	src/cc2.c \
	src/cc3.c \
	src/cc4.c \
	src/codegen_microcpu.c \
	src/host_compat.c

EMU_SRCS := \
	../microemu/microemu.c \
	../microemu/microcpu_core.c \
	../microemu/microcpu_core.h \
	../microemu/hc1200_mcu.c \
	../microemu/hc1200_mcu.h \
	../microemu/hc1200_cpu.c \
	../microemu/hc1200_cpu.h \
	../microemu/hc1200_microcomp.c \
	../microemu/hc1200_microcomp.h

TRACE_ARG := $(if $(filter 1,$(TRACE)),--trace,)
STRICT_ARG := $(if $(filter 1,$(STRICT)),--strict,)
TEST_ARG := $(if $(TEST),--test $(TEST),)
OBJECT_ARG := $(if $(filter 1,$(OBJECT_MODE)),--object-mode,)
TEST_RUNNER_ARGS := --expected tests/expected.txt \
	--expected-uart tests/expected_uart.txt \
	--input-uart tests/input_uart.txt --compiler $(CC_BIN) \
	--assembler $(ASM) --linker $(LD) --emulator $(EMU) --board $(EMU_BOARD) \
	--max-steps $(MAX_STEPS) --build-dir $(TEST_BUILD) \
	--include-dir tests/include --include-dir include --runtime-dir runtime

.PHONY: all test test-object test-multi selfhost-smoke assemble run clean

all: $(CC_BIN)

test: $(CC_BIN) $(ASM) $(LD) $(EMU)
	$(PYTHON) tests/run_tests.py $(TEST_RUNNER_ARGS) $(TRACE_ARG) $(OBJECT_ARG) $(TEST_ARG)

test-object:
	$(MAKE) test OBJECT_MODE=1

test-multi: $(CC_BIN) $(ASM) $(LD) $(EMU)
	$(PYTHON) tests/run_multi_tests.py --expected tests-multi/expected.txt \
		--compiler $(CC_BIN) --assembler $(ASM) --linker $(LD) \
		--emulator $(EMU) --board $(EMU_BOARD) \
		--max-steps $(MAX_STEPS) --build-dir $(MULTI_TEST_BUILD) \
		--include-dir tests/include --include-dir include \
		--runtime-dir runtime $(TRACE_ARG) $(TEST_ARG)

selfhost-smoke: $(CC_BIN) $(ASM)
	$(PYTHON) selfhost/run_smoke.py --compiler $(CC_BIN) \
		--assembler $(ASM) \
		--build-dir $(SELFHOST_BUILD) --include-dir include \
		--define SMALLC_SELFHOST \
		--timeout-seconds $(SELFHOST_TIMEOUT) \
		$(OBJECT_ARG) $(STRICT_ARG) $(SELFHOST_SRCS)

assemble: test

run: test

$(BUILD):
	mkdir -p $(BUILD)

$(ASM): ../asm/microasm.c
	$(MAKE) -C ../asm microasm

$(LD): ../asm/microlink.c
	$(MAKE) -C ../asm microlink

$(EMU): $(EMU_SRCS)
	$(MAKE) -C ../microemu microemu

$(CC_BIN): $(SRCS) src/cc.h src/notice.h src/host_compat.h src/smallc_proto.h | $(BUILD)
	$(HOSTCC) $(HOST_CFLAGS) -o $@ $(SRCS)

clean:
	rm -rf $(BUILD)

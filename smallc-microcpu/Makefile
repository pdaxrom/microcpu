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
PREPROCESS_MODE ?= 1

BUILD := build
TEST_BUILD := $(BUILD)/tests
MULTI_TEST_BUILD := $(BUILD)/tests-multi
SELFHOST_BUILD := $(BUILD)/selfhost-smoke
PCODE_BUILD := $(BUILD)/pcode
CPP_BIN := $(BUILD)/smallcpp
CC_ONLY_BIN := $(BUILD)/smallcc
PCINTERP_BIN := $(BUILD)/pcinterp

HOST_CFLAGS := -std=gnu89 -fsigned-char -Wall \
	-Wno-implicit-int -Wno-implicit-function-declaration \
	-Wno-int-conversion -Wno-incompatible-pointer-types \
	-Wno-return-type -Wno-parentheses -Wno-pointer-sign \
	-Wno-unused-value -Wno-unused-variable -Wno-format \
	-Wno-deprecated-non-prototype -Wno-pointer-integer-compare \
	-Wno-compare-distinct-pointer-types -Wno-empty-body

CPP_SRCS := \
	src/smallcpp_main.c \
	src/smallcpp_macro.c \
	src/smallcpp_io.c \
	src/shared_lex.c \
	src/shared_host_compat.c

CC_ONLY_SRCS := \
	src/smallcc_main.c \
	src/smallcc_driver.c \
	src/smallcc_input.c \
	src/smallcc_types.c \
	src/smallcc_decl.c \
	src/smallcc_func.c \
	src/smallcc_stmt.c \
	src/smallcc_lex.c \
	src/smallcc_expr.c \
	src/smallcc_emit.c \
	src/smallcc_codegen_microcpu.c \
	src/smallcc_codegen_pcode.c \
	src/shared_host_compat.c

SELFHOST_SRCS := \
	src/smallcpp_main.c \
	src/smallcpp_macro.c \
	src/smallcpp_io.c \
	src/shared_lex.c \
	src/smallcc_main.c \
	src/smallcc_driver.c \
	src/smallcc_input.c \
	src/smallcc_types.c \
	src/smallcc_decl.c \
	src/smallcc_func.c \
	src/smallcc_stmt.c \
	src/smallcc_lex.c \
	src/smallcc_expr.c \
	src/smallcc_emit.c \
	src/smallcc_codegen_microcpu.c \
	src/smallcc_codegen_pcode.c \
	src/shared_host_compat.c

SELFHOST_INPUTS := $(SELFHOST_SRCS)
SELFHOST_OBJECT_FILES := $(patsubst src/%.c,$(SELFHOST_BUILD)/%.o,$(SELFHOST_SRCS))
SELFHOST_CPP_OBJECT_FILES := \
	$(SELFHOST_BUILD)/smallcpp_main.o \
	$(SELFHOST_BUILD)/smallcpp_macro.o \
	$(SELFHOST_BUILD)/smallcpp_io.o \
	$(SELFHOST_BUILD)/shared_lex.o \
	$(SELFHOST_BUILD)/shared_host_compat.o
SELFHOST_CC_OBJECT_FILES := \
	$(SELFHOST_BUILD)/smallcc_main.o \
	$(SELFHOST_BUILD)/smallcc_driver.o \
	$(SELFHOST_BUILD)/smallcc_input.o \
	$(SELFHOST_BUILD)/smallcc_types.o \
	$(SELFHOST_BUILD)/smallcc_decl.o \
	$(SELFHOST_BUILD)/smallcc_func.o \
	$(SELFHOST_BUILD)/smallcc_stmt.o \
	$(SELFHOST_BUILD)/smallcc_lex.o \
	$(SELFHOST_BUILD)/smallcc_expr.o \
	$(SELFHOST_BUILD)/smallcc_emit.o \
	$(SELFHOST_BUILD)/smallcc_codegen_microcpu.o \
	$(SELFHOST_BUILD)/smallcc_codegen_pcode.o \
	$(SELFHOST_BUILD)/shared_host_compat.o

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
PREPROCESS_ARG := $(if $(filter 1,$(PREPROCESS_MODE)),--preprocess-mode,)
TEST_RUNNER_ARGS := --expected tests/expected.txt \
	--expected-uart tests/expected_uart.txt \
	--input-uart tests/input_uart.txt --compiler $(CC_ONLY_BIN) \
	--preprocessor $(CPP_BIN) --cc-only $(CC_ONLY_BIN) \
	--assembler $(ASM) --linker $(LD) --emulator $(EMU) --board $(EMU_BOARD) \
	--max-steps $(MAX_STEPS) --build-dir $(TEST_BUILD) \
	--include-dir tests/include --include-dir include --runtime-dir runtime

PCODE_TEST_RUNNER_ARGS := --expected pcode-tests/expected.txt \
	--expected-uart pcode-tests/expected_uart.txt \
	--preprocessor $(CPP_BIN) --cc-only $(CC_ONLY_BIN) \
	--pcinterp $(PCINTERP_BIN) --assembler $(ASM) \
	--build-dir $(PCODE_BUILD) --include-dir include

PCODE_MICROEMU_RUNNER_ARGS := --expected pcode-tests/expected.txt \
	--expected-uart pcode-tests/expected_uart.txt \
	--preprocessor $(CPP_BIN) --cc-only $(CC_ONLY_BIN) \
	--assembler $(ASM) --linker $(LD) --emulator $(EMU) \
	--board $(EMU_BOARD) --max-steps $(MAX_STEPS) \
	--build-dir $(BUILD)/pcode-microemu --include-dir include \
	--runtime-dir runtime

PCODE_NATIVE_RUNNER_ARGS := --expected pcode-tests-native/expected.txt \
	--preprocessor $(CPP_BIN) --cc-only $(CC_ONLY_BIN) \
	--assembler $(ASM) --linker $(LD) --emulator $(EMU) \
	--board $(EMU_BOARD) --max-steps $(MAX_STEPS) \
	--build-dir $(BUILD)/pcode-native --include-dir include \
	--runtime-dir runtime

.PHONY: all smallcpp smallcc test test-object test-multi test-preproc test-preprocessed test-pcode-host test-pcode-microemu test-pcode-native selfhost-smoke selfhost-link-smoke assemble run clean

all: $(CPP_BIN) $(CC_ONLY_BIN)

smallcpp: $(CPP_BIN)

smallcc: $(CC_ONLY_BIN)

test: $(CPP_BIN) $(CC_ONLY_BIN) $(ASM) $(LD) $(EMU)
	$(PYTHON) tests/run_tests.py $(TEST_RUNNER_ARGS) $(TRACE_ARG) $(OBJECT_ARG) $(PREPROCESS_ARG) $(TEST_ARG)

test-object:
	$(MAKE) test OBJECT_MODE=1

test-preproc: $(CPP_BIN)
	$(PYTHON) tests/run_preproc_tests.py --preprocessor $(CPP_BIN) \
		--build-dir $(BUILD)/tests-preproc \
		--include-dir tests-preproc/include --include-dir include

test-preprocessed: test-preproc
	$(MAKE) test PREPROCESS_MODE=1

test-multi: $(CPP_BIN) $(CC_ONLY_BIN) $(ASM) $(LD) $(EMU)
	$(PYTHON) tests/run_multi_tests.py --expected tests-multi/expected.txt \
		--compiler $(CC_ONLY_BIN) --preprocessor $(CPP_BIN) --cc-only $(CC_ONLY_BIN) \
		--assembler $(ASM) --linker $(LD) \
		--emulator $(EMU) --board $(EMU_BOARD) \
		--max-steps $(MAX_STEPS) --build-dir $(MULTI_TEST_BUILD) \
		--include-dir tests/include --include-dir include \
		--runtime-dir runtime $(TRACE_ARG) $(PREPROCESS_ARG) $(TEST_ARG)

test-pcode-host: $(CPP_BIN) $(CC_ONLY_BIN) $(PCINTERP_BIN) $(ASM)
	$(PYTHON) tests/run_pcode_tests.py $(PCODE_TEST_RUNNER_ARGS) \
		--max-steps $(MAX_STEPS) $(TEST_ARG)

test-pcode-microemu: $(CPP_BIN) $(CC_ONLY_BIN) $(ASM) $(LD) $(EMU)
	$(PYTHON) tests/run_pcode_microemu.py $(PCODE_MICROEMU_RUNNER_ARGS) \
		$(TEST_ARG)

test-pcode-native: $(CPP_BIN) $(CC_ONLY_BIN) $(ASM) $(LD) $(EMU)
	$(PYTHON) tests/run_pcode_native_tests.py $(PCODE_NATIVE_RUNNER_ARGS) \
		$(TEST_ARG)

selfhost-smoke: $(CPP_BIN) $(CC_ONLY_BIN) $(ASM)
	$(PYTHON) selfhost/run_smoke.py --compiler $(CC_ONLY_BIN) \
		--preprocessor $(CPP_BIN) --cc-only $(CC_ONLY_BIN) --preprocess-mode \
		--assembler $(ASM) \
		--build-dir $(SELFHOST_BUILD) --include-dir include \
		--define SMALLC_SELFHOST \
		--timeout-seconds $(SELFHOST_TIMEOUT) \
		$(OBJECT_ARG) $(STRICT_ARG) $(SELFHOST_INPUTS)

selfhost-link-smoke: $(CPP_BIN) $(CC_ONLY_BIN) $(ASM) $(LD)
	$(MAKE) selfhost-smoke OBJECT_MODE=1
	$(PYTHON) selfhost/link_smoke.py --assembler $(ASM) --linker $(LD) \
		--build-dir $(SELFHOST_BUILD) --runtime-dir runtime \
		$(STRICT_ARG) \
		--smallcpp-objects $(SELFHOST_CPP_OBJECT_FILES) \
		--smallcc-objects $(SELFHOST_CC_OBJECT_FILES)

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

$(CPP_BIN): $(CPP_SRCS) src/cc.h src/notice.h src/host_compat.h src/smallc_proto.h src/smallcc_globals.h | $(BUILD)
	$(HOSTCC) $(HOST_CFLAGS) -o $@ $(CPP_SRCS)

$(CC_ONLY_BIN): $(CC_ONLY_SRCS) src/cc.h src/notice.h src/host_compat.h src/smallc_proto.h src/smallcc_globals.h | $(BUILD)
	$(HOSTCC) $(HOST_CFLAGS) -o $@ $(CC_ONLY_SRCS)

$(PCINTERP_BIN): pcode/pcinterp.c | $(BUILD)
	$(HOSTCC) -std=gnu89 -Wall -Wno-unused-function \
		-Wno-deprecated-non-prototype -o $@ pcode/pcinterp.c

clean:
	rm -rf $(BUILD)

IVERILOG ?= iverilog
VVP      ?= vvp
OD       ?= od

ASM      = ../asm/microasm
MICROASM11_DIR ?= ../../../PROJECTS/k1801vm1/microasm11
ASM11    ?= $(MICROASM11_DIR)/microasm11
CORE_DIR ?= ../../../PROJECTS/k1801vm1
PYTHON   ?= python3
FIS_JOBS ?= 4
VSRC     = ../rtl/cpu.v tb.v
PROGRAMS = $(wildcard programs/*.asm)
TESTS    = $(patsubst programs/%.asm,%,$(PROGRAMS))
HEXES    = $(patsubst programs/%.asm,build/%.hex,$(PROGRAMS))
BOOTLOADER = ../bootloader/bootldr-mcu.asm
BOARD_STUBS = board/board_stubs.v
BOARD_MCU_VSRC = $(BOARD_STUBS) ../rtl/cpu.v ../boards/hc1200-mcu/uart.v ../boards/hc1200-mcu/gpio.v ../boards/hc1200-mcu/timer.v ../boards/hc1200-mcu/mcu.v board/tb_board_mcu.v
BOARD_MCU_BOOTLOAD_VSRC = $(BOARD_STUBS) ../rtl/cpu.v ../boards/hc1200-mcu/uart.v ../boards/hc1200-mcu/gpio.v ../boards/hc1200-mcu/timer.v ../boards/hc1200-mcu/mcu.v board/tb_board_mcu_bootload.v
BOARD_MICROCOMP_VSRC = $(BOARD_STUBS) ../rtl/cpu.v ../boards/hc1200-microcomp/uart.v ../boards/hc1200-microcomp/gpio.v ../boards/hc1200-microcomp/timer.v ../boards/hc1200-microcomp/microcomp.v board/tb_board_microcomp.v
J11_FRAM_VSRC = ../rtl/spi_fram_guest_ram.v spi_fram_model.v tb_spi_fram_guest_ram.v
J11_ENGINE_VSRC = ../rtl/j11_microengine.v ../rtl/spi_fram_guest_ram.v spi_fram_model.v tb_j11_microengine.v
J11_FETCH_VSRC = ../rtl/j11_microengine.v ../rtl/spi_fram_guest_ram.v spi_fram_model.v tb_j11_fetch.v
J11_EXECUTE_VSRC = ../rtl/j11_microengine.v ../rtl/spi_fram_guest_ram.v spi_fram_model.v tb_j11_execute.v
J11_BUS_VSRC = ../rtl/spi_fram_guest_ram.v ../boards/hc1200-microcomp/uart.v ../boards/hc1200-microcomp/j11_guest_bus.v spi_fram_model.v tb_j11_guest_bus.v
J11_PERIPHERAL_VSRC = ../rtl/j11_microengine.v $(filter-out tb_j11_guest_bus.v,$(J11_BUS_VSRC)) tb_j11_peripherals.v
J11_CPU_IO_VSRC = $(filter-out tb_j11_peripherals.v,$(J11_PERIPHERAL_VSRC)) tb_j11_cpu_io.v
J11_BOARD_VSRC = $(BOARD_STUBS) ../rtl/j11_microengine.v ../rtl/spi_fram_guest_ram.v ../boards/hc1200-microcomp/uart.v ../boards/hc1200-microcomp/j11_guest_bus.v ../boards/hc1200-microcomp/j11_microcomp.v spi_fram_model.v board/tb_board_j11_microcomp.v
J11_BOARD_EXECUTE_VSRC = $(BOARD_STUBS) ../rtl/j11_microengine.v ../rtl/spi_fram_guest_ram.v ../boards/hc1200-microcomp/uart.v ../boards/hc1200-microcomp/j11_guest_bus.v ../boards/hc1200-microcomp/j11_microcomp.v spi_fram_model.v board/tb_board_j11_execute.v
J11_ENGINE_ASM = ucode/j11_microengine_smoke.asm
J11_UCODE_ASM = ../ucode/j11.asm
include ../ucode/config.mk
IVERILOG += -DJ11_UROM_WORDS=$(J11_UROM_WORDS)
J11_GUEST_PROGRAMS = $(wildcard j11_programs/*.asm)
J11_GUEST_HEXES = $(patsubst j11_programs/%.asm,build/guest_%.hex,$(J11_GUEST_PROGRAMS))

.PHONY: all test clean bootloader-smoke bootloader-save bootloader-go bootloader-load board-smoke board-mcu-smoke board-mcu-bootload-rx board-microcomp-memmap j11-test j11-fram-test j11-engine-test j11-fetch-test j11-execute-test j11-bus-test j11-board-test j11-board-execute-test j11-board-ucode check-microasm11
.DELETE_ON_ERROR:

all: tb.vvp

build/tb_j11_execute.vvp build/tb_j11_cpu_io.vvp build/tb_j11_nofis.vvp \
build/tb_j11_peripherals.vvp build/tb_j11_fis.vvp build/tb_j11_core_reference.vvp \
build/tb_j11_halt.vvp: include/j11_context_probe.vh

test: tb.vvp $(HEXES) bootloader-smoke bootloader-save bootloader-go bootloader-load board-smoke j11-test
	@fail=0; \
	for test in $(TESTS); do \
		echo "==> $$test"; \
		if ! $(VVP) tb.vvp +PROGRAM=build/$$test.hex; then \
			fail=1; \
		fi; \
	done; \
	exit $$fail

tb.vvp: $(VSRC)
	$(IVERILOG) -g2012 -o $@ $(VSRC)

$(ASM): ../asm/microasm.c ../asm/cpu_target.h
	$(MAKE) -C ../asm microasm

build:
	mkdir -p $@

build/%.bin: programs/%.asm include/test.inc ../asm/include/pseudo.inc $(ASM) | build
	$(ASM) -binary $< $@ > build/$*.asm.log 2>&1 || { cat build/$*.asm.log; exit 1; }

build/%.hex: build/%.bin
	{ printf '@0000\n'; $(OD) -An -tx1 -v $<; printf '@ffff\n00\n'; } > $@

build/bootldr-mcu.bin: $(BOOTLOADER) ../asm/include/pseudo.inc ../asm/include/devmap.inc $(ASM) | build
	$(ASM) -binary $< $@ > build/bootldr-mcu.asm.log 2>&1 || { cat build/bootldr-mcu.asm.log; exit 1; }

build/bootldr-mcu.hex: build/bootldr-mcu.bin
	{ printf '@0000\n'; $(OD) -An -tx1 -v $<; printf '@ffff\n00\n'; } > $@

build/bootldr-mcu-board.hex: build/bootldr-mcu.bin
	{ printf '@0000\n'; $(OD) -An -tx1 -v $<; printf '@07ff\n00\n'; } > $@

bootloader-smoke: tb.vvp build/bootldr-mcu.hex
	$(VVP) tb.vvp +PROGRAM=build/bootldr-mcu.hex +BOOT_BANNER +TIMEOUT=20000

bootloader-save: tb.vvp build/bootldr-mcu.hex
	$(VVP) tb.vvp +PROGRAM=build/bootldr-mcu.hex +BOOT_SAVE +TIMEOUT=30000

bootloader-go: tb.vvp build/bootldr-mcu.hex
	$(VVP) tb.vvp +PROGRAM=build/bootldr-mcu.hex +BOOT_GO +TIMEOUT=30000

bootloader-load: tb.vvp build/bootldr-mcu.hex
	$(VVP) tb.vvp +PROGRAM=build/bootldr-mcu.hex +BOOT_LOAD +TIMEOUT=30000

board-smoke: board-mcu-smoke board-mcu-bootload-rx board-microcomp-memmap

build/board_uart_smoke.bin: board_programs/board_uart_smoke.asm ../asm/include/pseudo.inc ../asm/include/devmap.inc $(ASM) | build
	$(ASM) -binary $< $@ > build/board_uart_smoke.asm.log 2>&1 || { cat build/board_uart_smoke.asm.log; exit 1; }

build/board_uart_smoke.hex: build/board_uart_smoke.bin
	{ printf '@0000\n'; $(OD) -An -tx1 -v $<; printf '@07ff\n00\n'; } > $@

build/board_uart_rx_payload.bin: board_programs/board_uart_rx_payload.asm ../asm/include/pseudo.inc ../asm/include/devmap.inc $(ASM) | build
	$(ASM) -binary $< $@ > build/board_uart_rx_payload.asm.log 2>&1 || { cat build/board_uart_rx_payload.asm.log; exit 1; }

build/board_uart_rx_payload.hex: build/board_uart_rx_payload.bin
	{ printf '@0000\n'; $(OD) -An -tx1 -v $<; } > $@

build/microcomp_memmap.bin: board_programs/microcomp_memmap.asm ../asm/include/pseudo.inc ../asm/include/devmap.inc $(ASM) | build
	$(ASM) -binary $< $@ > build/microcomp_memmap.asm.log 2>&1 || { cat build/microcomp_memmap.asm.log; exit 1; }

build/microcomp_memmap.hex: build/microcomp_memmap.bin
	{ printf '@0000\n'; $(OD) -An -tx1 -v $<; printf '@07ff\n00\n'; } > $@

build/board_mcu.vvp: $(BOARD_MCU_VSRC) | build
	$(IVERILOG) -g2012 -s tb_board_mcu -o $@ $(BOARD_MCU_VSRC)

build/board_mcu_bootload.vvp: $(BOARD_MCU_BOOTLOAD_VSRC) | build
	$(IVERILOG) -g2012 -s tb_board_mcu_bootload -o $@ $(BOARD_MCU_BOOTLOAD_VSRC)

build/board_microcomp.vvp: $(BOARD_MICROCOMP_VSRC) | build
	$(IVERILOG) -g2012 -s tb_board_microcomp -o $@ $(BOARD_MICROCOMP_VSRC)

board-mcu-smoke: build/board_mcu.vvp build/board_uart_smoke.hex
	$(VVP) build/board_mcu.vvp +SRAM_HEX=build/board_uart_smoke.hex

board-mcu-bootload-rx: build/board_mcu_bootload.vvp build/bootldr-mcu-board.hex build/board_uart_rx_payload.hex
	$(VVP) build/board_mcu_bootload.vvp +SRAM_HEX=build/bootldr-mcu-board.hex +PAYLOAD_HEX=build/board_uart_rx_payload.hex

board-microcomp-memmap: build/board_microcomp.vvp build/microcomp_memmap.hex
	$(VVP) build/board_microcomp.vvp +SRAM_HEX=build/microcomp_memmap.hex

j11-test: j11-alu-test j11-pc-test j11-shift-test j11-ebr-pack-test j11-context-test j11-fram-test j11-engine-test j11-fetch-test j11-execute-test j11-bus-test j11-peripherals-test j11-cpu-io-test j11-halt-test j11-fis-test j11-board-test j11-board-execute-test j11-board-ucode

.PHONY: j11-context-test
build/j11_context_memory.bin: ucode/j11_context_memory.asm ../ucode/config.mk ../asm/include/pseudo.inc $(ASM) | build
	$(ASM) --cpu j11 -D J11_CODE_WORDS=$(J11_UCODE_WORDS) -binary $< $@ > build/j11_context_memory.asm.log 2>&1 || { cat build/j11_context_memory.asm.log; exit 1; }

build/j11_context_memory.words: build/j11_context_memory.bin ../ucode/make_urom_ebr.py ../ucode/config.mk
	$(PYTHON) ../ucode/make_urom_ebr.py $< --words $(J11_UROM_WORDS) --format mem > $@

build/j11_context_urom_ebr.v: build/j11_context_memory.bin ../ucode/make_urom_ebr.py ../ucode/config.mk
	$(PYTHON) ../ucode/make_urom_ebr.py $< --words $(J11_UROM_WORDS) > $@

build/tb_j11_context_memory.vvp: tb_j11_context_memory.v ../rtl/j11_microengine.v include/j11_context_probe.vh ../ucode/config.mk | build
	$(IVERILOG) -g2012 -Wall -s tb_j11_context_memory -o $@ $(filter %.v,$^)

j11-context-test: build/tb_j11_context_memory.vvp build/j11_context_memory.words
	$(VVP) build/tb_j11_context_memory.vvp

.PHONY: j11-halt-test
build/tb_j11_halt.vvp: tb_j11_halt.v ../rtl/j11_microengine.v ../ucode/config.mk | build
	$(IVERILOG) -g2012 -Wall -s tb_j11_halt -o $@ $(filter %.v,$^)

j11-halt-test: build/tb_j11_halt.vvp build/tb_j11_cpu_io.vvp build/j11_ucode.words build/guest_halt_console.hex build/guest_halt_privileged.hex
	$(VVP) build/tb_j11_halt.vvp
	$(VVP) build/tb_j11_cpu_io.vvp +PROGRAM=build/guest_halt_privileged.hex

.PHONY: j11-shift-test
build/tb_j11_shift.vvp: tb_j11_shift.v ../rtl/j11_microengine.v | build
	$(IVERILOG) -g2012 -Wall -s tb_j11_shift -o $@ $^

j11-shift-test: build/tb_j11_shift.vvp
	$(VVP) build/tb_j11_shift.vvp

.PHONY: j11-pc-test
build/tb_j11_pc.vvp: tb_j11_pc.v ../rtl/j11_microengine.v | build
	$(IVERILOG) -g2012 -Wall -s tb_j11_pc -o $@ $^

j11-pc-test: build/tb_j11_pc.vvp
	$(VVP) build/tb_j11_pc.vvp

.PHONY: j11-alu-test
build/tb_j11_alu.vvp: tb_j11_alu.v ../rtl/j11_microengine.v | build
	$(IVERILOG) -g2012 -Wall -s tb_j11_alu -o $@ $^

j11-alu-test: build/tb_j11_alu.vvp
	$(VVP) build/tb_j11_alu.vvp

.PHONY: j11-ebr-pack-test
j11-ebr-pack-test:
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) test_urom_ebr.py

.PHONY: j11-cpu-io-test
build/tb_j11_cpu_io.vvp: $(J11_CPU_IO_VSRC) ../ucode/config.mk | build
	$(IVERILOG) -g2012 -Wall -s tb_j11_cpu_io -o $@ $(J11_CPU_IO_VSRC)

j11-cpu-io-test: build/tb_j11_cpu_io.vvp build/j11_ucode.words build/guest_cpu_registers.hex build/guest_cpu_psw.hex build/guest_cpu_pirq.hex build/guest_cpu_stack.hex build/guest_cpu_nxm.hex build/guest_register_sets.hex
	$(VVP) build/tb_j11_cpu_io.vvp +PROGRAM=build/guest_cpu_registers.hex
	$(VVP) build/tb_j11_cpu_io.vvp +PROGRAM=build/guest_cpu_psw.hex
	$(VVP) build/tb_j11_cpu_io.vvp +PROGRAM=build/guest_register_sets.hex
	$(VVP) build/tb_j11_cpu_io.vvp +PROGRAM=build/guest_cpu_pirq.hex
	$(VVP) build/tb_j11_cpu_io.vvp +PROGRAM=build/guest_cpu_stack.hex
	$(VVP) build/tb_j11_cpu_io.vvp +PROGRAM=build/guest_cpu_nxm.hex +FAULT_READ=06000 +FAULT_WRITE=2 +EXPECT_CAUSE=4 +EXPECT_CPUERR=0154

.PHONY: j11-fis-test j11-fis-reference-test j11-nofis-test
build/tb_j11_fis.vvp: tb_j11_fis.v ../rtl/j11_microengine.v ../ucode/config.mk | build
	$(IVERILOG) -g2012 -Wall -s tb_j11_fis -o $@ $(filter %.v,$^)

build/guest_fis.bin: j11_programs/fis_test.inc

j11-fis-test: build/tb_j11_cpu_io.vvp build/tb_j11_fis.vvp build/j11_ucode.words build/guest_fis.hex build/guest_fis_edges.hex build/guest_fis_faults.hex build/guest_fis_partial_write.hex
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) -m unittest test_fis_reference
	$(VVP) build/tb_j11_cpu_io.vvp +PROGRAM=build/guest_fis.hex
	$(VVP) build/tb_j11_cpu_io.vvp +PROGRAM=build/guest_fis_edges.hex
	$(VVP) build/tb_j11_fis.vvp +PROGRAM=build/guest_fis_faults.hex +FAULT_READ=06006
	$(VVP) build/tb_j11_fis.vvp +PROGRAM=build/guest_fis_faults.hex +FAULT_WRITE=06004
	$(VVP) build/tb_j11_fis.vvp +PROGRAM=build/guest_fis_partial_write.hex +FAULT_WRITE=06006

# Larger arithmetic corpus is separate from the quick regression target.
j11-fis-reference-test: build/tb_j11_fis.vvp build/j11_ucode.words check-microasm11
	$(PYTHON) run_fis_reference.py --asm11 $(ASM11) --vvp $(VVP) --jobs $(FIS_JOBS)

# Optional strict profile keeps FIS opcodes reserved; never overwrites the
# production ROM or the generated board image.
build/j11_nofis.bin: $(J11_UCODE_ASM) $(wildcard ../ucode/j11_*.asm ../ucode/j11_*.inc) ../ucode/config.mk ../asm/include/pseudo.inc $(ASM) | build
	$(ASM) --cpu j11 -D J11_DISABLE_FIS -binary $< $@ > build/j11_nofis.asm.log 2>&1 || { cat build/j11_nofis.asm.log; exit 1; }
	@size=$$(wc -c < $@); test $$size -le $$((2 * $(J11_UCODE_WORDS))) || { echo "J-11 microcode is $$size bytes; code limit is $$((2 * $(J11_UCODE_WORDS))) (64 words reserved for context)"; exit 1; }

build/j11_nofis.words: build/j11_nofis.bin ../ucode/make_urom_ebr.py ../ucode/config.mk
	$(PYTHON) ../ucode/make_urom_ebr.py $< --words $(J11_UROM_WORDS) --format mem > $@

build/tb_j11_nofis.vvp: $(J11_CPU_IO_VSRC) ../ucode/config.mk | build
	$(IVERILOG) -g2012 -Wall -s tb_j11_cpu_io -Ptb_j11_cpu_io.UCODE_FILE='"build/j11_nofis.words"' -o $@ $(J11_CPU_IO_VSRC)

j11-nofis-test: build/tb_j11_nofis.vvp build/j11_nofis.words build/guest_fis_unavailable.hex
	$(VVP) build/tb_j11_nofis.vvp +PROGRAM=build/guest_fis_unavailable.hex

.PHONY: j11-peripherals-test
build/tb_j11_peripherals.vvp: $(J11_PERIPHERAL_VSRC) ../ucode/config.mk | build
	$(IVERILOG) -g2012 -Wall -s tb_j11_peripherals -o $@ $(J11_PERIPHERAL_VSRC)

j11-peripherals-test: build/tb_j11_peripherals.vvp build/j11_ucode.words build/guest_peripherals.hex build/guest_peripherals_wait_masked.hex
	$(VVP) build/tb_j11_peripherals.vvp

build/tb_spi_fram_guest_ram.vvp: $(J11_FRAM_VSRC) | build
	$(IVERILOG) -g2012 -Wall -s tb_spi_fram_guest_ram -o $@ $(J11_FRAM_VSRC)

j11-fram-test: build/tb_spi_fram_guest_ram.vvp
	$(VVP) build/tb_spi_fram_guest_ram.vvp
	@set -e; for divider in 2 3 5 17; do \
		$(IVERILOG) -g2012 -Wall -s tb_spi_fram_guest_ram \
			-Ptb_spi_fram_guest_ram.CLK_DIV=$$divider \
			-o build/tb_spi_fram_guest_ram_$$divider.vvp $(J11_FRAM_VSRC); \
		$(VVP) build/tb_spi_fram_guest_ram_$$divider.vvp; \
	done

build/j11_microengine_smoke.bin: $(J11_ENGINE_ASM) ../asm/include/pseudo.inc $(ASM) | build
	$(ASM) --cpu j11 -binary $< $@ > build/j11_microengine_smoke.asm.log 2>&1 || { cat build/j11_microengine_smoke.asm.log; exit 1; }

build/j11_microengine_smoke.words: build/j11_microengine_smoke.bin ../ucode/make_urom_ebr.py
	$(PYTHON) ../ucode/make_urom_ebr.py $< --words 1024 --format mem > $@

build/tb_j11_microengine.vvp: $(J11_ENGINE_VSRC) | build
	$(IVERILOG) -g2012 -Wall -s tb_j11_microengine -o $@ $(J11_ENGINE_VSRC)

j11-engine-test: build/tb_j11_microengine.vvp build/j11_microengine_smoke.words
	$(VVP) build/tb_j11_microengine.vvp

build/j11_ucode.bin: $(J11_UCODE_ASM) $(wildcard ../ucode/j11_*.asm ../ucode/j11_*.inc) ../ucode/config.mk ../asm/include/pseudo.inc $(ASM) | build
	$(ASM) --cpu j11 -binary --list build/j11_ucode.lst $< $@ > build/j11_ucode.asm.log 2>&1 || { cat build/j11_ucode.asm.log; exit 1; }
	@size=$$(wc -c < $@); test $$size -le $$((2 * $(J11_UCODE_WORDS))) || { echo "J-11 microcode is $$size bytes; code limit is $$((2 * $(J11_UCODE_WORDS))) (64 words reserved for context)"; exit 1; }

build/j11_ucode.words: build/j11_ucode.bin ../ucode/make_urom_ebr.py ../ucode/config.mk
	$(PYTHON) ../ucode/make_urom_ebr.py $< --words $(J11_UROM_WORDS) --format mem > $@

check-microasm11:
	@test -x "$(ASM11)" || { echo "microasm11 not found: $(ASM11)"; exit 1; }

build/guest_%.bin: j11_programs/%.asm | build check-microasm11
	$(ASM11) -binary --cpu dcj-11 --list build/guest_$*.lst $< $@ > build/guest_$*.asm.log 2>&1 || { cat build/guest_$*.asm.log; exit 1; }

$(J11_GUEST_HEXES): build/guest_%.hex: build/guest_%.bin
	{ printf '@0000\n'; $(OD) -An -tx1 -v $<; } > $@

j11-board-ucode:
	$(MAKE) -C ../boards j11-ucode

.PHONY: j11-core-test j11-core-banks-test
build/core_reference_export: core_reference.c $(CORE_DIR)/tests/core_tests.c $(CORE_DIR)/core/core.c $(CORE_DIR)/core/core.h $(CORE_DIR)/core/disas.c $(CORE_DIR)/core/hardware.c $(CORE_DIR)/core/pdp11_fp.c | build
	$(CC) -Wall -Wpedantic -g -DENABLE_MMU=0 -I$(CORE_DIR) core_reference.c $(CORE_DIR)/core/core.c $(CORE_DIR)/core/disas.c $(CORE_DIR)/core/hardware.c -o $@

build/tb_j11_core_reference.vvp: tb_j11_core_reference.v ../rtl/j11_microengine.v ../ucode/config.mk | build
	$(IVERILOG) -g2012 -Wall -s tb_j11_core_reference -o $@ $(filter %.v,$^)

j11-core-test: build/core_reference_export build/tb_j11_core_reference.vvp build/j11_ucode.words check-microasm11
	$(PYTHON) run_core_reference.py --asm11 $(ASM11) --vvp $(VVP)

j11-core-banks-test: build/core_reference_export build/tb_j11_core_reference.vvp build/j11_ucode.words check-microasm11
	$(PYTHON) run_core_reference.py --asm11 $(ASM11) --vvp $(VVP) --banks

# Optional verification of the exact hardware ROM against Lattice's models.
# On the Mac, point LATTICE_SIM_DIR at a copy from the installed Diamond.
LATTICE_SIM_DIR ?= $(HOME)/.local/lscc/diamond/3.14/cae_library/simulation/verilog/machxo2
J11_EBR_VSRC = ../boards/hc1200-microcomp/j11_urom_ebr.v
J11_EBR_FLAGS = -DJ11_EBR_UROM -y $(LATTICE_SIM_DIR)

.PHONY: j11-ebr-test
j11-ebr-test: j11-board-ucode build/j11_ucode.words build/j11_context_urom_ebr.v build/core_reference_export $(J11_GUEST_HEXES)
	@test -f "$(LATTICE_SIM_DIR)/PDPW8KC.v" || { echo "Set LATTICE_SIM_DIR to Diamond's MachXO2 Verilog models"; exit 1; }
	$(IVERILOG) -g2012 -Wall -s tb_j11_urom_ebr -o build/tb_j11_urom_ebr.vvp $(J11_EBR_FLAGS) tb_j11_urom_ebr.v $(J11_EBR_VSRC)
	$(VVP) build/tb_j11_urom_ebr.vvp
	$(IVERILOG) -g2012 -Wall -s tb_j11_context_memory -o build/tb_j11_context_memory_ebr.vvp $(J11_EBR_FLAGS) tb_j11_context_memory.v ../rtl/j11_microengine.v build/j11_context_urom_ebr.v
	$(VVP) build/tb_j11_context_memory_ebr.vvp
	$(IVERILOG) -g2012 -Wall -s tb_j11_halt -o build/tb_j11_halt_ebr.vvp $(J11_EBR_FLAGS) tb_j11_halt.v ../rtl/j11_microengine.v $(J11_EBR_VSRC)
	$(VVP) build/tb_j11_halt_ebr.vvp
	$(IVERILOG) -g2012 -Wall -s tb_j11_execute -o build/tb_j11_execute_ebr.vvp $(J11_EBR_FLAGS) $(J11_EXECUTE_VSRC) $(J11_EBR_VSRC)
	$(VVP) build/tb_j11_execute_ebr.vvp
	$(IVERILOG) -g2012 -Wall -s tb_j11_cpu_io -o build/tb_j11_cpu_io_ebr.vvp $(J11_EBR_FLAGS) $(J11_CPU_IO_VSRC) $(J11_EBR_VSRC)
	@for test in cpu_registers cpu_psw register_sets halt_privileged cpu_pirq cpu_stack fis fis_edges; do \
		$(VVP) build/tb_j11_cpu_io_ebr.vvp +PROGRAM=build/guest_$$test.hex || exit 1; \
	done
	$(VVP) build/tb_j11_cpu_io_ebr.vvp +PROGRAM=build/guest_cpu_nxm.hex +FAULT_READ=06000 +FAULT_WRITE=2 +EXPECT_CAUSE=4 +EXPECT_CPUERR=0154
	$(IVERILOG) -g2012 -Wall -s tb_j11_fis -o build/tb_j11_fis_ebr.vvp $(J11_EBR_FLAGS) tb_j11_fis.v ../rtl/j11_microengine.v $(J11_EBR_VSRC)
	$(VVP) build/tb_j11_fis_ebr.vvp +PROGRAM=build/guest_fis_faults.hex +FAULT_READ=06006
	$(VVP) build/tb_j11_fis_ebr.vvp +PROGRAM=build/guest_fis_faults.hex +FAULT_WRITE=06004
	$(VVP) build/tb_j11_fis_ebr.vvp +PROGRAM=build/guest_fis_partial_write.hex +FAULT_WRITE=06006
	$(IVERILOG) -g2012 -Wall -s tb_j11_core_reference -o build/tb_j11_core_reference_ebr.vvp $(J11_EBR_FLAGS) tb_j11_core_reference.v ../rtl/j11_microengine.v $(J11_EBR_VSRC)
	$(PYTHON) run_core_reference.py --asm11 $(ASM11) --vvp $(VVP) --banks --testbench build/tb_j11_core_reference_ebr.vvp

build/tb_j11_fetch.vvp: $(J11_FETCH_VSRC) ../ucode/config.mk | build
	$(IVERILOG) -g2012 -Wall -s tb_j11_fetch -o $@ $(J11_FETCH_VSRC)

j11-fetch-test: build/tb_j11_fetch.vvp build/j11_ucode.words build/guest_fetch.hex
	$(VVP) build/tb_j11_fetch.vvp

build/tb_j11_execute.vvp: $(J11_EXECUTE_VSRC) ../ucode/config.mk | build
	$(IVERILOG) -g2012 -Wall -s tb_j11_execute -o $@ $(J11_EXECUTE_VSRC)

j11-execute-test: build/tb_j11_execute.vvp build/j11_ucode.words build/guest_basic.hex build/guest_reserved.hex build/guest_bus_error.hex build/guest_interrupt.hex build/guest_irq_priority.hex build/guest_branches.hex build/guest_mov_register.hex build/guest_mov_zero.hex build/guest_mov_immediate.hex build/guest_mov_deferred.hex build/guest_mov_modes.hex build/guest_movb_modes.hex build/guest_clear_test.hex build/guest_double_ops.hex build/guest_ea_timing.hex build/guest_bic_bis.hex build/guest_control_flow.hex build/guest_control_traps.hex build/guest_sob.hex build/guest_software_traps.hex build/guest_com.hex build/guest_inc_dec.hex build/guest_neg_adc_sbc.hex build/guest_shift_rotate.hex build/guest_swab.hex build/guest_sxt.hex build/guest_xor.hex build/guest_psw.hex build/guest_system.hex build/guest_reset_rtt.hex build/guest_mul.hex build/guest_ash.hex build/guest_ashc.hex build/guest_div.hex build/guest_mark_lock.hex build/guest_previous_space.hex build/guest_privileged.hex \
	build/guest_mark_edges.hex build/guest_lock_edges.hex build/guest_trace_return.hex build/guest_sp_banks.hex
	$(VVP) build/tb_j11_execute.vvp

build/tb_j11_guest_bus.vvp: $(J11_BUS_VSRC) | build
	$(IVERILOG) -g2012 -Wall -s tb_j11_guest_bus -o $@ $(J11_BUS_VSRC)

j11-bus-test: build/tb_j11_guest_bus.vvp
	$(VVP) build/tb_j11_guest_bus.vvp

build/tb_board_j11_microcomp.vvp: $(J11_BOARD_VSRC) | build
	$(IVERILOG) -g2012 -Wall -s tb_board_j11_microcomp -o $@ $(J11_BOARD_VSRC)

j11-board-test: build/tb_board_j11_microcomp.vvp build/j11_microengine_smoke.words
	$(VVP) build/tb_board_j11_microcomp.vvp

build/tb_board_j11_execute.vvp: $(J11_BOARD_EXECUTE_VSRC) | build
	$(IVERILOG) -g2012 -Wall -s tb_board_j11_execute -o $@ $(J11_BOARD_EXECUTE_VSRC)

j11-board-execute-test: build/tb_board_j11_execute.vvp build/j11_ucode.words build/guest_dl11_tx.hex
	$(VVP) build/tb_board_j11_execute.vvp

run-%: tb.vvp build/%.hex
	$(VVP) tb.vvp +PROGRAM=build/$*.hex

vcd-%: tb.vvp build/%.hex
	$(VVP) tb.vvp +PROGRAM=build/$*.hex +VCD=build/$*.vcd

clean:
	rm -rf build *.vvp *.vcd

# New specialized CPU, separate RTL, firmware and output paths.
J11_V2_DEPS = $(wildcard ../ucode/v2/*.asm ../ucode/v2/*.inc) ../ucode/config.mk
J11_V2_FLAGS = -DUCODE_WORD_PC -DJ11_ENGINE_MODULE=ucode_cpu -DJ11_BOARD_MODULE=ucode_hc1200_microcomp \
	-DJ11_UCODE_FILE='"build/j11_ucode_v2.words"'
J11_V2_COMMON = ../rtl/ucode_cpu.v ../rtl/spi_fram_guest_ram.v \
	../boards/hc1200-microcomp/uart.v ../boards/hc1200-microcomp/j11_guest_bus.v spi_fram_model.v
J11_V2_TESTS = j11_alu j11_fetch j11_execute j11_cpu_io j11_peripherals j11_halt j11_fis j11_core_reference
J11_TARGET_HEADER = include/j11_test_target.vh

$(addprefix build/tb_,$(addsuffix .vvp,$(J11_V2_TESTS))) build/tb_board_j11_execute.vvp: $(J11_TARGET_HEADER)

build/j11_ucode_v2.bin: ../ucode/v2/j11.asm $(J11_V2_DEPS) $(ASM) | build
	$(ASM) --cpu ucode -binary --list build/j11_ucode_v2.lst $< $@ > build/j11_ucode_v2.asm.log 2>&1 || { cat build/j11_ucode_v2.asm.log; exit 1; }

build/j11_ucode_v2.words: build/j11_ucode_v2.bin ../ucode/make_urom_ebr.py ../ucode/config.mk
	$(PYTHON) ../ucode/make_urom_ebr.py $< --words $(J11_UROM_WORDS) --format mem > $@

build/ucode_%.vvp: tb_%.v $(J11_V2_COMMON) $(J11_TARGET_HEADER) include/j11_context_probe.vh ../ucode/config.mk | build
	$(IVERILOG) -g2012 -Wall -s tb_$* $(J11_V2_FLAGS) -o $@ $< $(J11_V2_COMMON)

build/ucode_board.vvp: board/tb_board_j11_execute.v $(J11_V2_COMMON) $(BOARD_STUBS) ../boards/hc1200-microcomp/ucode_microcomp.v $(J11_TARGET_HEADER) ../ucode/config.mk | build
	$(IVERILOG) -g2012 -Wall -s tb_board_j11_execute $(J11_V2_FLAGS) -o $@ $(filter %.v,$^)

build/ucode_native.bin: ucode/ucode_native.asm ../ucode/v2/pseudo.inc $(ASM) | build
	$(ASM) --cpu ucode -binary $< $@ > build/ucode_native.asm.log 2>&1 || { cat build/ucode_native.asm.log; exit 1; }

build/ucode_native.words: build/ucode_native.bin ../ucode/make_urom_ebr.py ../ucode/config.mk
	$(PYTHON) ../ucode/make_urom_ebr.py $< --words $(J11_UROM_WORDS) --format mem > $@

.PHONY: ucode-test ucode-native-test ucode-j11-test ucode-core-test ucode-fis-reference-test ucode-nofis-test
ucode-native-test: build/ucode_ucode_native.vvp build/ucode_native.words build/ucode_j11_alu.vvp build/ucode_ucode_datapath.vvp
	$(VVP) build/ucode_ucode_native.vvp
	$(VVP) build/ucode_j11_alu.vvp
	$(VVP) build/ucode_ucode_datapath.vvp

ucode-j11-test: $(addprefix build/ucode_,$(addsuffix .vvp,$(filter-out j11_core_reference,$(J11_V2_TESTS)))) build/ucode_board.vvp build/j11_ucode_v2.words $(J11_GUEST_HEXES)
	$(VVP) build/ucode_j11_fetch.vvp
	$(VVP) build/ucode_j11_execute.vvp
	$(VVP) build/ucode_j11_peripherals.vvp
	$(VVP) build/ucode_j11_halt.vvp
	$(VVP) build/ucode_board.vvp
	@set -e; for test in cpu_registers cpu_psw register_sets halt_privileged cpu_pirq cpu_stack fis fis_edges; do \
		$(VVP) build/ucode_j11_cpu_io.vvp +PROGRAM=build/guest_$$test.hex; \
	done
	$(VVP) build/ucode_j11_cpu_io.vvp +PROGRAM=build/guest_cpu_nxm.hex +FAULT_READ=06000 +FAULT_WRITE=2 +EXPECT_CAUSE=4 +EXPECT_CPUERR=0154
	$(VVP) build/ucode_j11_fis.vvp +PROGRAM=build/guest_fis_faults.hex +FAULT_READ=06006
	$(VVP) build/ucode_j11_fis.vvp +PROGRAM=build/guest_fis_faults.hex +FAULT_WRITE=06004
	$(VVP) build/ucode_j11_fis.vvp +PROGRAM=build/guest_fis_partial_write.hex +FAULT_WRITE=06006

ucode-core-test: build/core_reference_export build/ucode_j11_core_reference.vvp build/j11_ucode_v2.words check-microasm11
	$(PYTHON) run_core_reference.py --asm11 $(ASM11) --vvp $(VVP) --banks --testbench build/ucode_j11_core_reference.vvp --listing build/j11_ucode_v2.lst --work-dir build/ucode_core_reference

ucode-fis-reference-test: build/ucode_j11_fis.vvp build/j11_ucode_v2.words check-microasm11
	$(PYTHON) run_fis_reference.py --asm11 $(ASM11) --vvp $(VVP) --testbench build/ucode_j11_fis.vvp --work-dir build/ucode_fis_reference --jobs $(FIS_JOBS)

build/j11_v2_nofis.bin: ../ucode/v2/j11.asm $(J11_V2_DEPS) $(ASM) | build
	$(ASM) --cpu ucode -D J11_DISABLE_FIS -binary $< $@ > build/j11_v2_nofis.asm.log 2>&1 || { cat build/j11_v2_nofis.asm.log; exit 1; }

build/j11_v2_nofis.words: build/j11_v2_nofis.bin ../ucode/make_urom_ebr.py ../ucode/config.mk
	$(PYTHON) ../ucode/make_urom_ebr.py $< --words $(J11_UROM_WORDS) --format mem > $@

build/ucode_nofis.vvp: tb_j11_cpu_io.v $(J11_V2_COMMON) $(J11_TARGET_HEADER) include/j11_context_probe.vh ../ucode/config.mk | build
	$(IVERILOG) -g2012 -Wall -s tb_j11_cpu_io $(J11_V2_FLAGS) -Ptb_j11_cpu_io.UCODE_FILE='"build/j11_v2_nofis.words"' -o $@ $< $(J11_V2_COMMON)

ucode-nofis-test: build/ucode_nofis.vvp build/j11_v2_nofis.words build/guest_fis_unavailable.hex
	$(VVP) build/ucode_nofis.vvp +PROGRAM=build/guest_fis_unavailable.hex

ucode-test: ucode-native-test ucode-j11-test ucode-nofis-test

# Identical guest image and bus latency, deterministic native-clock counts.
.PHONY: ucode-benchmark-test profile-acceptance profile-acceptance-ebr
ucode-benchmark-test: build/tb_j11_fis.vvp build/ucode_j11_fis.vvp build/j11_ucode.words build/j11_ucode_v2.words build/guest_benchmark.hex
	$(VVP) build/tb_j11_fis.vvp +PROGRAM=build/guest_benchmark.hex
	$(VVP) build/ucode_j11_fis.vvp +PROGRAM=build/guest_benchmark.hex

# Sub-makes are deliberately sequential: shared core fixture directories
# must not be regenerated while a different suite is reading them.
profile-acceptance:
	$(PYTHON) check_preserved_profiles.py
	$(MAKE) -C ../asm test
	$(MAKE) test j11-core-banks-test j11-nofis-test
	$(MAKE) ucode-test ucode-core-test ucode-benchmark-test
	$(MAKE) j11-fis-reference-test ucode-fis-reference-test

profile-acceptance-ebr: profile-acceptance
	$(MAKE) j11-ebr-test
	$(MAKE) ucode-ebr-test

# Optional exact EBR simulation on the Mac; this does not run Diamond.
J11_V2_EBR = ../boards/hc1200-microcomp/ucode_urom_ebr.v
J11_V2_EBR_FLAGS = $(J11_V2_FLAGS) $(J11_EBR_FLAGS) -DJ11_EBR_MODULE=ucode_urom_ebr
.PHONY: ucode-board-ucode ucode-ebr-test
ucode-board-ucode:
	$(MAKE) -C ../boards j11-v2-ucode

build/ucode_native_ebr.v: build/ucode_native.bin ../ucode/make_urom_ebr.py ../ucode/config.mk
	$(PYTHON) ../ucode/make_urom_ebr.py $< --words $(J11_UROM_WORDS) --module-name ucode_urom_ebr > $@

ucode-ebr-test: ucode-board-ucode build/ucode_native_ebr.v build/j11_ucode_v2.words build/core_reference_export $(J11_GUEST_HEXES)
	@test -f "$(LATTICE_SIM_DIR)/PDPW8KC.v" || { echo "Set LATTICE_SIM_DIR to Diamond's MachXO2 Verilog models"; exit 1; }
	$(IVERILOG) -g2012 -Wall -s tb_j11_urom_ebr -o build/ucode_pack_ebr.vvp $(J11_V2_EBR_FLAGS) tb_j11_urom_ebr.v $(J11_V2_EBR)
	$(VVP) build/ucode_pack_ebr.vvp
	$(IVERILOG) -g2012 -Wall -s tb_ucode_native -o build/ucode_native_ebr.vvp $(J11_V2_EBR_FLAGS) tb_ucode_native.v ../rtl/ucode_cpu.v build/ucode_native_ebr.v
	$(VVP) build/ucode_native_ebr.vvp
	@set -e; for test in j11_execute j11_peripherals j11_halt; do \
		$(IVERILOG) -g2012 -Wall -s tb_$$test -o build/ucode_$${test}_ebr.vvp $(J11_V2_EBR_FLAGS) tb_$$test.v $(J11_V2_COMMON) $(J11_V2_EBR); \
		$(VVP) build/ucode_$${test}_ebr.vvp; \
	done
	$(IVERILOG) -g2012 -Wall -s tb_j11_cpu_io -o build/ucode_cpu_io_ebr.vvp $(J11_V2_EBR_FLAGS) tb_j11_cpu_io.v $(J11_V2_COMMON) $(J11_V2_EBR)
	@set -e; for test in cpu_registers cpu_psw register_sets halt_privileged cpu_pirq cpu_stack fis fis_edges; do \
		$(VVP) build/ucode_cpu_io_ebr.vvp +PROGRAM=build/guest_$$test.hex; \
	done
	$(IVERILOG) -g2012 -Wall -s tb_j11_core_reference -o build/ucode_core_ebr.vvp $(J11_V2_EBR_FLAGS) tb_j11_core_reference.v ../rtl/ucode_cpu.v $(J11_V2_EBR)
	$(PYTHON) run_core_reference.py --asm11 $(ASM11) --vvp $(VVP) --banks --testbench build/ucode_core_ebr.vvp --listing build/j11_ucode_v2.lst --work-dir build/ucode_core_ebr

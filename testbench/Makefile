IVERILOG ?= iverilog
VVP      ?= vvp
OD       ?= od

ASM      = ../asm/microasm
MICROASM11_DIR ?= ../../../PROJECTS/k1801vm1/microasm11
ASM11    ?= $(MICROASM11_DIR)/microasm11
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
J11_BOARD_VSRC = $(BOARD_STUBS) ../rtl/j11_microengine.v ../rtl/spi_fram_guest_ram.v ../boards/hc1200-microcomp/uart.v ../boards/hc1200-microcomp/j11_guest_bus.v ../boards/hc1200-microcomp/j11_microcomp.v spi_fram_model.v board/tb_board_j11_microcomp.v
J11_BOARD_EXECUTE_VSRC = $(BOARD_STUBS) ../rtl/j11_microengine.v ../rtl/spi_fram_guest_ram.v ../boards/hc1200-microcomp/uart.v ../boards/hc1200-microcomp/j11_guest_bus.v ../boards/hc1200-microcomp/j11_microcomp.v spi_fram_model.v board/tb_board_j11_execute.v
J11_ENGINE_ASM = ucode/j11_microengine_smoke.asm
J11_UCODE_ASM = ../ucode/j11.asm
J11_UROM_WORDS = 2048
J11_GUEST_PROGRAMS = $(wildcard j11_programs/*.asm)
J11_GUEST_HEXES = $(patsubst j11_programs/%.asm,build/guest_%.hex,$(J11_GUEST_PROGRAMS))

.PHONY: all test clean bootloader-smoke bootloader-save bootloader-go bootloader-load board-smoke board-mcu-smoke board-mcu-bootload-rx board-microcomp-memmap j11-test j11-fram-test j11-engine-test j11-fetch-test j11-execute-test j11-bus-test j11-board-test j11-board-execute-test j11-board-ucode check-microasm11

all: tb.vvp

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

$(ASM): ../asm/microasm.c
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

j11-test: j11-fram-test j11-engine-test j11-fetch-test j11-execute-test j11-bus-test j11-board-test j11-board-execute-test j11-board-ucode

build/tb_spi_fram_guest_ram.vvp: $(J11_FRAM_VSRC) | build
	$(IVERILOG) -g2012 -Wall -s tb_spi_fram_guest_ram -o $@ $(J11_FRAM_VSRC)

j11-fram-test: build/tb_spi_fram_guest_ram.vvp
	$(VVP) build/tb_spi_fram_guest_ram.vvp

build/j11_microengine_smoke.bin: $(J11_ENGINE_ASM) ../asm/include/pseudo.inc $(ASM) | build
	$(ASM) -binary $< $@ > build/j11_microengine_smoke.asm.log 2>&1 || { cat build/j11_microengine_smoke.asm.log; exit 1; }

build/j11_microengine_smoke.words: build/j11_microengine_smoke.bin
	{ printf '@0000\n'; $(OD) -An -v -tx2 $< | sed 's/[[:space:]]*$$//'; printf '@03ff\n00b0\n'; } > $@

build/tb_j11_microengine.vvp: $(J11_ENGINE_VSRC) | build
	$(IVERILOG) -g2012 -Wall -s tb_j11_microengine -o $@ $(J11_ENGINE_VSRC)

j11-engine-test: build/tb_j11_microengine.vvp build/j11_microengine_smoke.words
	$(VVP) build/tb_j11_microengine.vvp

build/j11_ucode.bin: $(J11_UCODE_ASM) ../asm/include/pseudo.inc $(ASM) | build
	$(ASM) -binary $< $@ > build/j11_ucode.asm.log 2>&1 || { cat build/j11_ucode.asm.log; exit 1; }
	@size=$$(wc -c < $@); test $$size -le $$((2 * $(J11_UROM_WORDS))) || { echo "J-11 microcode is $$size bytes; limit is $$((2 * $(J11_UROM_WORDS)))"; exit 1; }

build/j11_ucode.words: build/j11_ucode.bin
	{ printf '@0000\n'; $(OD) -An -v -tx2 $< | sed 's/[[:space:]]*$$//'; printf '@%04x\n00b0\n' $$(( $(J11_UROM_WORDS) - 1 )); } > $@

check-microasm11:
	@test -x "$(ASM11)" || { echo "microasm11 not found: $(ASM11)"; exit 1; }

build/guest_%.bin: j11_programs/%.asm | build check-microasm11
	$(ASM11) -binary --cpu dcj-11 --list build/guest_$*.lst $< $@ > build/guest_$*.asm.log 2>&1 || { cat build/guest_$*.asm.log; exit 1; }

$(J11_GUEST_HEXES): build/guest_%.hex: build/guest_%.bin
	{ printf '@0000\n'; $(OD) -An -tx1 -v $<; } > $@

j11-board-ucode:
	$(MAKE) -C ../boards j11-ucode

build/tb_j11_fetch.vvp: $(J11_FETCH_VSRC) | build
	$(IVERILOG) -g2012 -Wall -s tb_j11_fetch -o $@ $(J11_FETCH_VSRC)

j11-fetch-test: build/tb_j11_fetch.vvp build/j11_ucode.words build/guest_fetch.hex
	$(VVP) build/tb_j11_fetch.vvp

build/tb_j11_execute.vvp: $(J11_EXECUTE_VSRC) | build
	$(IVERILOG) -g2012 -Wall -s tb_j11_execute -o $@ $(J11_EXECUTE_VSRC)

j11-execute-test: build/tb_j11_execute.vvp build/j11_ucode.words build/guest_basic.hex build/guest_reserved.hex build/guest_bus_error.hex build/guest_interrupt.hex build/guest_irq_priority.hex build/guest_branches.hex build/guest_mov_register.hex build/guest_mov_zero.hex build/guest_mov_immediate.hex build/guest_mov_deferred.hex build/guest_mov_modes.hex build/guest_movb_modes.hex build/guest_clear_test.hex build/guest_double_ops.hex build/guest_ea_timing.hex build/guest_bic_bis.hex build/guest_control_flow.hex build/guest_control_traps.hex build/guest_sob.hex build/guest_software_traps.hex build/guest_com.hex build/guest_inc_dec.hex build/guest_neg_adc_sbc.hex build/guest_shift_rotate.hex build/guest_swab.hex build/guest_sxt.hex build/guest_xor.hex build/guest_psw.hex build/guest_system.hex
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

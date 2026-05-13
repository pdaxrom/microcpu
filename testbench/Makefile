IVERILOG ?= iverilog
VVP      ?= vvp
OD       ?= od

ASM      = ../asm/microasm
VSRC     = ../rtl/cpu.v tb.v
PROGRAMS = $(wildcard programs/*.asm)
TESTS    = $(patsubst programs/%.asm,%,$(PROGRAMS))
HEXES    = $(patsubst programs/%.asm,build/%.hex,$(PROGRAMS))
BOOTLOADER = ../bootloader/bootldr-mcu.asm
BOARD_STUBS = board/board_stubs.v
BOARD_MCU_VSRC = $(BOARD_STUBS) ../rtl/cpu.v ../boards/hc1200-mcu/uart.v ../boards/hc1200-mcu/gpio.v ../boards/hc1200-mcu/timer.v ../boards/hc1200-mcu/mcu.v board/tb_board_mcu.v
BOARD_MCU_BOOTLOAD_VSRC = $(BOARD_STUBS) ../rtl/cpu.v ../boards/hc1200-mcu/uart.v ../boards/hc1200-mcu/gpio.v ../boards/hc1200-mcu/timer.v ../boards/hc1200-mcu/mcu.v board/tb_board_mcu_bootload.v
BOARD_MICROCOMP_VSRC = $(BOARD_STUBS) ../rtl/cpu.v ../boards/hc1200-microcomp/uart.v ../boards/hc1200-microcomp/gpio.v ../boards/hc1200-microcomp/timer.v ../boards/hc1200-microcomp/microcomp.v board/tb_board_microcomp.v

.PHONY: all test clean bootloader-smoke bootloader-save bootloader-go bootloader-load board-smoke board-mcu-smoke board-mcu-bootload-rx board-microcomp-memmap

all: tb.vvp

test: tb.vvp $(HEXES) bootloader-smoke bootloader-save bootloader-go bootloader-load board-smoke
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

run-%: tb.vvp build/%.hex
	$(VVP) tb.vvp +PROGRAM=build/$*.hex

vcd-%: tb.vvp build/%.hex
	$(VVP) tb.vvp +PROGRAM=build/$*.hex +VCD=build/$*.vcd

clean:
	rm -rf build *.vvp *.vcd

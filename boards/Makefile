ifneq (Microsoft, $(findstring Microsoft, $(shell uname -r)))
DIAMOND_HOME ?= $(HOME)/.local/lscc/diamond/3.14
DIAMOND_LIBSTDCPP ?= /lib/x86_64-linux-gnu/libstdc++.so.6
SCUBACMD = $(DIAMOND_HOME)/ispfpga/bin/lin64/scuba
FOUNDRY  = $(DIAMOND_HOME)/ispfpga
SCUBA = \
	export LD_PRELOAD="$(DIAMOND_LIBSTDCPP)"; \
	export LD_LIBRARY_PATH="$(DIAMOND_HOME)/tcltk/lib:$(DIAMOND_HOME)/ispfpga/bin/lin64:$(DIAMOND_HOME)/bin/lin64"; \
	export FOUNDRY="$(FOUNDRY)"; \
	$(SCUBACMD)
else
DIAMOND_HOME ?= /mnt/Storage/Games/lscc/diamond/3.10_x64
SCUBACMD = $(DIAMOND_HOME)/ispfpga/bin/nt64/scuba.exe
FOUNDRY  = $(DIAMOND_HOME)/ispfpga
SCUBA = \
	export FOUNDRY="$(FOUNDRY)"; \
	export WSLENV="$WSLENV:FOUNDRY/l"; \
	$(SCUBACMD)
endif

MICROASM ?= ../asm/microasm
OD ?= od
J11_UROM_WORDS = 1024
J11_UCODE_ASM = ../ucode/j11.asm
J11_UCODE_BIN = hc1200-microcomp/j11_ucode.bin
J11_UCODE_MEM = hc1200-microcomp/j11_ucode.mem

.PHONY: all clean j11-ucode

all: hc1200/sram.v hc1200-mcu/sram.v hc1200-mcu/srampages.v hc1200-microcomp/sram.v hc1200-microcomp/srampages.v $(J11_UCODE_MEM)

$(MICROASM): ../asm/microasm.c
	$(MAKE) -C ../asm microasm

$(J11_UCODE_BIN): $(J11_UCODE_ASM) ../asm/include/pseudo.inc $(MICROASM)
	$(MICROASM) -binary $(J11_UCODE_ASM) $@
	@size=$$(wc -c < $@); test $$size -le $$((2 * $(J11_UROM_WORDS))) || { echo "J-11 microcode is $$size bytes; limit is $$((2 * $(J11_UROM_WORDS)))"; exit 1; }

$(J11_UCODE_MEM): $(J11_UCODE_BIN)
	{ printf '@0000\n'; $(OD) -An -v -tx2 $< | sed 's/[[:space:]]*$$//'; printf '@03ff\n00b0\n'; } > $@

j11-ucode: $(J11_UCODE_MEM)

.INTERMEDIATE: $(J11_UCODE_BIN)

hc1200/sram.v: sram-mcu.mem
	cd hc1200 && \
	$(SCUBA) -w -n sram -lang verilog -synth lse -bus_exp 7 -bb -arch xo2c00 -type ramdq -device LCMXO2-1200HC -addr_width 11 -data_width 8 -num_words 2048 -cascade -11 -memfile ../sram-mcu.mem -memformat orca -writemode NORMAL

hc1200-mcu/sram.v: sram-mcu.mem
	cd hc1200-mcu && \
	$(SCUBA) -w -n sram -lang verilog -synth lse -bus_exp 7 -bb -arch xo2c00 -type ramdq -device LCMXO2-1200HC -addr_width 11 -data_width 8 -num_words 2048 -cascade -11 -memfile ../sram-mcu.mem -memformat orca -writemode NORMAL

hc1200-mcu/srampages.v:
	cd hc1200-mcu && \
	$(SCUBA) -w -n srampages -lang verilog -synth lse -bus_exp 7 -bb -arch xo2c00 -type ramdq -device LCMXO2-1200HC -addr_width 12 -data_width 8 -num_words 4096 -cascade -1 -meminit0 -writemode NORMAL

hc1200-microcomp/sram.v: sram.mem
	cd hc1200-microcomp && \
	$(SCUBA) -w -n sram -lang verilog -synth lse -bus_exp 7 -bb -arch xo2c00 -type ramdq -device LCMXO2-1200HC -addr_width 11 -data_width 8 -num_words 2048 -cascade -11 -memfile ../sram.mem -memformat orca -writemode NORMAL

hc1200-microcomp/srampages.v:
	cd hc1200-microcomp && \
	$(SCUBA) -w -n srampages -lang verilog -synth lse -bus_exp 7 -bb -arch xo2c00 -type ramdq -device LCMXO2-1200HC -addr_width 12 -data_width 8 -num_words 4096 -cascade -1 -meminit0 -writemode NORMAL

clean:
	rm -f *.mem $(J11_UCODE_BIN) $(J11_UCODE_MEM) hc1200/sram.v hc1200-mcu/sram.v hc1200-mcu/srampages.v hc1200-microcomp/sram.v hc1200-microcomp/srampages.v

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
PYTHON ?= python3
include ../ucode/config.mk
J11_UCODE_ASM = ../ucode/j11.asm
J11_UCODE_BIN = hc1200-microcomp/j11_ucode.bin
J11_UCODE_MEM = hc1200-microcomp/j11_ucode.mem
J11_UCODE_EBR = hc1200-microcomp/j11_urom_ebr.v

.PHONY: all clean j11-ucode j11-diamond
.DELETE_ON_ERROR:

all: hc1200/sram.v hc1200-mcu/sram.v hc1200-mcu/srampages.v hc1200-microcomp/sram.v hc1200-microcomp/srampages.v $(J11_UCODE_MEM) $(J11_UCODE_EBR) hc1200-microcomp

$(MICROASM): ../asm/microasm.c ../asm/cpu_target.h
	$(MAKE) -C ../asm microasm

$(J11_UCODE_BIN): $(J11_UCODE_ASM) $(wildcard ../ucode/j11_*.asm ../ucode/j11_*.inc) ../ucode/config.mk ../asm/include/pseudo.inc $(MICROASM)
	$(MICROASM) --cpu j11 -binary $(J11_UCODE_ASM) $@
	@size=$$(wc -c < $@); test $$size -le $$((2 * $(J11_UCODE_WORDS))) || { echo "J-11 microcode is $$size bytes; code limit is $$((2 * $(J11_UCODE_WORDS))) (64 words reserved for context)"; exit 1; }

$(J11_UCODE_MEM): $(J11_UCODE_BIN) ../ucode/make_urom_ebr.py ../ucode/config.mk
	$(PYTHON) ../ucode/make_urom_ebr.py $< --words $(J11_UROM_WORDS) --format mem > $@

$(J11_UCODE_EBR): $(J11_UCODE_BIN) ../ucode/make_urom_ebr.py ../ucode/config.mk
	$(PYTHON) ../ucode/make_urom_ebr.py $< --words $(J11_UROM_WORDS) > $@

j11-ucode: $(J11_UCODE_MEM) $(J11_UCODE_EBR)

j11-diamond: j11-ucode
	cd hc1200-microcomp && \
	LD_PRELOAD="$(DIAMOND_LIBSTDCPP)" "$(DIAMOND_HOME)/bin/lin64/diamondc" build-j11.tcl

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
	rm -f $(DIAG_BIN) $(DIAG_MEM) $(DIAG_EBR) hc1200-microcomp/sd_fram_diag.lst
	rm -f $(J11_V2_BIN) $(J11_V2_MEM) $(J11_V2_EBR) $(SD_BIN) $(SD_NOFIS_BIN) hc1200-microcomp/j11_sd.mem hc1200-microcomp/j11_sd_nofis.mem hc1200-microcomp/sd_urom_ebr.v hc1200-microcomp/sd_nofis_urom_ebr.v *.mem $(J11_UCODE_BIN) $(J11_UCODE_MEM) $(J11_UCODE_EBR) hc1200/sram.v hc1200-mcu/sram.v hc1200-microcomp/srampages.v hc1200-microcomp/sram.v hc1200-microcomp/srampages.v

# Independent images for the new CPU; never overwrite the reference J-11 ROM.
J11_V2_ASM = ../ucode/v2/j11.asm
J11_V2_BIN = hc1200-microcomp/j11_ucode_v2.bin
J11_V2_MEM = hc1200-microcomp/j11_ucode_v2.mem
J11_V2_EBR = hc1200-microcomp/ucode_urom_ebr.v

.PHONY: j11-v2-ucode
$(J11_V2_BIN): $(J11_V2_ASM) $(wildcard ../ucode/v2/*.asm ../ucode/v2/*.inc) ../ucode/config.mk $(MICROASM)
	$(MICROASM) --cpu ucode -binary $(J11_V2_ASM) $@
	@size=$$(wc -c < $@); test $$size -le $$((2 * $(J11_UCODE_WORDS))) || { echo "New microcode exceeds $(J11_UCODE_WORDS) words"; exit 1; }

$(J11_V2_MEM): $(J11_V2_BIN) ../ucode/make_urom_ebr.py ../ucode/config.mk
	$(PYTHON) ../ucode/make_urom_ebr.py $< --words $(J11_UROM_WORDS) --format mem > $@

$(J11_V2_EBR): $(J11_V2_BIN) ../ucode/make_urom_ebr.py ../ucode/config.mk
	$(PYTHON) ../ucode/make_urom_ebr.py $< --words $(J11_UROM_WORDS) --module-name ucode_urom_ebr > $@

j11-v2-ucode: $(J11_V2_MEM) $(J11_V2_EBR)

.INTERMEDIATE: $(J11_V2_BIN)

.PHONY: j11-v2-diamond
j11-v2-diamond: j11-v2-ucode
	cd hc1200-microcomp && \
	LD_PRELOAD="$(DIAMOND_LIBSTDCPP)" "$(DIAMOND_HOME)/bin/lin64/diamondc" build-ucode.tcl

include sd.mk
include diagnostics.mk

.PHONY: hc1200-microcomp hc1200-microcomp-diamond hc1200-microcomp-original
hc1200-microcomp: disk-ucode
hc1200-microcomp-original: hc1200-microcomp/sram.v hc1200-microcomp/srampages.v
hc1200-microcomp-diamond: hc1200-microcomp
	cd hc1200-microcomp && \
	LD_PRELOAD="$(DIAMOND_LIBSTDCPP)" "$(DIAMOND_HOME)/bin/lin64/diamondc" build-microcomp.tcl

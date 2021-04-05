DIAMOND_VERSION=3.11_x64

ifneq (Microsoft, $(findstring Microsoft, $(shell uname -r)))
SCUBACMD = /usr/local/diamond/$(DIAMOND_VERSION)/ispfpga/bin/lin64/scuba
FOUNDRY  = /usr/local/diamond/$(DIAMOND_VERSION)/ispfpga
SCUBA = \
	export LD_LIBRARY_PATH="/usr/local/diamond/$(DIAMOND_VERSION)/tcltk/lib:/usr/local/diamond/$(DIAMOND_VERSION)/ispfpga/bin/lin64:/usr/local/diamond/$(DIAMOND_VERSION)/bin/lin64:/usr/local/diamond/$(DIAMOND_VERSION)/ispfpga/bin/lin64"; \
	export FOUNDRY="$(FOUNDRY)"; \
	$(SCUBACMD)
else
SCUBACMD = /mnt/Storage/Games/lscc/diamond/3.10_x64/ispfpga/bin/nt64/scuba.exe
FOUNDRY  = /mnt/Storage/Games/lscc/diamond/3.10_x64/ispfpga
SCUBA = \
	export FOUNDRY="$(FOUNDRY)"; \
	export WSLENV="$WSLENV:FOUNDRY/l"; \
	$(SCUBACMD)
endif

all: hc1200/sram.v hc1200-mcu/sram.v hc1200-mcu/srampages.v hc1200-microcomp/sram.v hc1200-microcomp/srampages.v

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
	rm -f *.mem hc1200/sram.v hc1200-mcu/sram.v hc1200-mcu/srampages.v hc1200-microcomp/sram.v hc1200-microcomp/srampages.v

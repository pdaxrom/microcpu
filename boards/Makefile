ifneq (Microsoft, $(findstring Microsoft, $(shell uname -r)))
SCUBACMD = /usr/local/diamond/3.11_x64/ispfpga/bin/lin64/scuba
FOUNDRY  = /usr/local/diamond/3.11_x64/ispfpga
SCUBA = \
	export LD_LIBRARY_PATH="/usr/local/diamond/3.11_x64/tcltk/lib:/usr/local/diamond/3.11_x64/ispfpga/bin/lin64:/usr/local/diamond/3.11_x64/bin/lin64:/usr/local/diamond/3.11_x64/ispfpga/bin/lin64"; \
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

all: hc1200/sram.v

microcomp: hc1200-microcomp/sram.v

hc1200/sram.v: sram.mem
	cd hc1200 && \
	$(SCUBA) -w -n sram -lang verilog -synth lse -bus_exp 7 -bb -arch xo2c00 -type ramdq -device LCMXO2-1200HC -addr_width 11 -data_width 8 -num_words 2048 -cascade -11 -memfile ../sram.mem -memformat orca -writemode NORMAL

hc1200-microcomp/sram.v: sram.mem
	cd hc1200-microcomp && \
	$(SCUBA) -w -n sram -lang verilog -synth lse -bus_exp 7 -bb -arch xo2c00 -type ramdq -device LCMXO2-1200HC -addr_width 11 -data_width 8 -num_words 2048 -cascade -11 -memfile ../sram.mem -memformat orca -writemode NORMAL

clean:
	rm -f *.mem hc1200/sram.v hc1200-microcomp/sram.v

all: tb.vvp

VSRC = ../rtl/cpu.v ../asm/sram.v tb.v

clean:
	rm -f *.vvp *.vcd

tb.vvp: $(VSRC)
	iverilog -o $@ $(VSRC)

IVERILOG ?= iverilog
VVP      ?= vvp
OD       ?= od

ASM      = ../asm/microasm
VSRC     = ../rtl/cpu.v tb.v
PROGRAMS = $(wildcard programs/*.asm)
TESTS    = $(patsubst programs/%.asm,%,$(PROGRAMS))
HEXES    = $(patsubst programs/%.asm,build/%.hex,$(PROGRAMS))
BOOTLOADER = ../bootloader/bootldr-mcu.asm

.PHONY: all test clean

all: tb.vvp

test: tb.vvp $(HEXES) bootloader-smoke
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

bootloader-smoke: tb.vvp build/bootldr-mcu.hex
	$(VVP) tb.vvp +PROGRAM=build/bootldr-mcu.hex +BOOT_BANNER +TIMEOUT=20000

run-%: tb.vvp build/%.hex
	$(VVP) tb.vvp +PROGRAM=build/$*.hex

vcd-%: tb.vvp build/%.hex
	$(VVP) tb.vvp +PROGRAM=build/$*.hex +VCD=build/$*.vcd

clean:
	rm -rf build *.vvp *.vcd

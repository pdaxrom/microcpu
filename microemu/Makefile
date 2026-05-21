CC ?= cc
CFLAGS ?= -std=c99 -Wall -Wpedantic -O2 -g
LDFLAGS ?=
ASM ?= ../asm/microasm
PYTHON ?= python3

.PHONY: all examples run-hello run-echo run-calc run-calc-fis16 run-calc-fis32 run-boot-calc-fis32 run-ram64 clean

OBJS = microemu.o microcpu_core.o hc1200_mcu.o hc1200_cpu.o hc1200_microcomp.o
EXAMPLES = hello_world uart_echo calc32 calc_fis16 calc_fis32 ram64
EXAMPLE_BINS = $(patsubst %,build/examples/%.bin,$(EXAMPLES))

all: microemu

examples: $(EXAMPLE_BINS)

microemu: $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS)

microemu.o: microemu.c microcpu_core.h hc1200_mcu.h hc1200_cpu.h hc1200_microcomp.h
	$(CC) $(CFLAGS) -c -o $@ $<

microcpu_core.o: microcpu_core.c microcpu_core.h
	$(CC) $(CFLAGS) -c -o $@ $<

hc1200_mcu.o: hc1200_mcu.c hc1200_mcu.h microcpu_core.h
	$(CC) $(CFLAGS) -c -o $@ $<

hc1200_cpu.o: hc1200_cpu.c hc1200_cpu.h hc1200_mcu.h microcpu_core.h
	$(CC) $(CFLAGS) -c -o $@ $<

hc1200_microcomp.o: hc1200_microcomp.c hc1200_microcomp.h hc1200_mcu.h microcpu_core.h
	$(CC) $(CFLAGS) -c -o $@ $<

$(ASM): ../asm/microasm.c
	$(MAKE) -C ../asm microasm

build:
	mkdir -p $@

build/examples:
	mkdir -p $@

build/boot:
	mkdir -p $@

build/examples/%.bin: examples/%.asm ../asm/include/pseudo.inc ../asm/include/devmap.inc ../asm/include/int32.inc ../asm/include/fis.inc ../asm/include/fis16.inc ../asm/include/fis32.inc $(ASM) | build/examples
	$(ASM) -binary $< $@ > $@.log 2>&1 || { cat $@.log; exit 1; }

build/calc_fis32_0800.asm: examples/calc_fis32.asm scripts/set_org.py | build
	$(PYTHON) scripts/set_org.py --org 0x0800 $< $@

build/calc_fis32_0800.bin: build/calc_fis32_0800.asm ../asm/include/pseudo.inc ../asm/include/devmap.inc ../asm/include/int32.inc ../asm/include/fis32.inc $(ASM) | build
	$(ASM) -binary $< $@ > $@.log 2>&1 || { cat $@.log; exit 1; }

build/boot/calc_fis32_0800.uart: build/calc_fis32_0800.bin scripts/boot_uart.py | build/boot
	$(PYTHON) scripts/boot_uart.py --start 0x0800 --append-text "1.5 2 *\nq" --output $@ $<

run-hello: microemu build/examples/hello_world.bin
	./microemu --format bin --stop-on-self-branch build/examples/hello_world.bin

run-echo: microemu build/examples/uart_echo.bin
	./microemu --format bin --stop-on-self-branch --uart-rx "A" build/examples/uart_echo.bin

run-calc: microemu build/examples/calc32.bin
	./microemu --format bin --stop-on-self-branch --uart-rx "12 34 +\nq" build/examples/calc32.bin

run-calc-fis16: microemu build/examples/calc_fis16.bin
	./microemu --format bin --stop-on-self-branch --uart-rx "1.5 2 *\nq" build/examples/calc_fis16.bin

run-calc-fis32: microemu build/examples/calc_fis32.bin
	./microemu --format bin --stop-on-self-branch --uart-rx "1.5 2 *\nq" build/examples/calc_fis32.bin

run-boot-calc-fis32: microemu build/boot/calc_fis32_0800.uart
	./microemu --board hc1200-microcomp --format auto --stdin-rx --stop-on-self-branch --max-steps 200000000 ../boards/sram.mem < build/boot/calc_fis32_0800.uart

run-ram64: microemu build/examples/ram64.bin
	./microemu --board hc1200-cpu --format bin --stop-on-self-branch build/examples/ram64.bin

clean:
	rm -f microemu $(OBJS)
	rm -rf build

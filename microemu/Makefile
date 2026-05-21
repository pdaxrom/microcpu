CC ?= cc
CFLAGS ?= -std=c99 -Wall -Wpedantic -O2 -g
LDFLAGS ?=
ASM ?= ../asm/microasm

.PHONY: all examples run-hello run-echo run-calc run-calc-fis16 run-calc-fis32 run-ram64 clean

OBJS = microemu.o microcpu_core.o hc1200_mcu.o hc1200_cpu.o
EXAMPLES = hello_world uart_echo calc32 calc_fis16 calc_fis32 ram64
EXAMPLE_BINS = $(patsubst %,build/examples/%.bin,$(EXAMPLES))

all: microemu

examples: $(EXAMPLE_BINS)

microemu: $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS)

microemu.o: microemu.c microcpu_core.h hc1200_mcu.h hc1200_cpu.h
	$(CC) $(CFLAGS) -c -o $@ $<

microcpu_core.o: microcpu_core.c microcpu_core.h
	$(CC) $(CFLAGS) -c -o $@ $<

hc1200_mcu.o: hc1200_mcu.c hc1200_mcu.h microcpu_core.h
	$(CC) $(CFLAGS) -c -o $@ $<

hc1200_cpu.o: hc1200_cpu.c hc1200_cpu.h hc1200_mcu.h microcpu_core.h
	$(CC) $(CFLAGS) -c -o $@ $<

$(ASM): ../asm/microasm.c
	$(MAKE) -C ../asm microasm

build/examples:
	mkdir -p $@

build/examples/%.bin: examples/%.asm ../asm/include/pseudo.inc ../asm/include/devmap.inc ../asm/include/int32.inc ../asm/include/fis.inc ../asm/include/fis16.inc ../asm/include/fis32.inc $(ASM) | build/examples
	$(ASM) -binary $< $@ > $@.log 2>&1 || { cat $@.log; exit 1; }

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

run-ram64: microemu build/examples/ram64.bin
	./microemu --board hc1200-cpu --format bin --stop-on-self-branch build/examples/ram64.bin

clean:
	rm -f microemu $(OBJS)
	rm -rf build

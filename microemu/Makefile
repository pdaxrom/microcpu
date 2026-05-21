CC ?= cc
CFLAGS ?= -std=c99 -Wall -Wpedantic -O2 -g
LDFLAGS ?=
ASM ?= ../asm/microasm

.PHONY: all examples run-hello run-echo clean

OBJS = microemu.o microcpu_core.o hc1200_mcu.o
EXAMPLES = hello_world uart_echo calc32
EXAMPLE_BINS = $(patsubst %,build/examples/%.bin,$(EXAMPLES))

all: microemu

examples: $(EXAMPLE_BINS)

microemu: $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS)

microemu.o: microemu.c microcpu_core.h hc1200_mcu.h
	$(CC) $(CFLAGS) -c -o $@ $<

microcpu_core.o: microcpu_core.c microcpu_core.h
	$(CC) $(CFLAGS) -c -o $@ $<

hc1200_mcu.o: hc1200_mcu.c hc1200_mcu.h microcpu_core.h
	$(CC) $(CFLAGS) -c -o $@ $<

$(ASM): ../asm/microasm.c
	$(MAKE) -C ../asm microasm

build/examples:
	mkdir -p $@

build/examples/%.bin: examples/%.asm ../asm/include/pseudo.inc ../asm/include/devmap.inc $(ASM) | build/examples
	$(ASM) -binary $< $@ > $@.log 2>&1 || { cat $@.log; exit 1; }

run-hello: microemu build/examples/hello_world.bin
	./microemu --format bin --stop-on-self-branch build/examples/hello_world.bin

run-echo: microemu build/examples/uart_echo.bin
	./microemu --format bin --stop-on-self-branch --uart-rx "A" build/examples/uart_echo.bin

run-calc: microemu build/examples/calc32.bin
	./microemu --format bin --stop-on-self-branch --uart-rx "12 34 +\nq" build/examples/calc32.bin

clean:
	rm -f microemu $(OBJS)
	rm -rf build

TARGET = microasm microlink microdis

MODULES = modules/display.bin

all: $(TARGET) $(MODULES)

CFLAGS = -Wall -Wpedantic -g

LDFLAGS = -g

MICROASM_OBJS = microasm.o
MICROLINK_OBJS = microlink.o
MICRODIS_OBJS = microdis.o

microasm: $(MICROASM_OBJS)
	$(CC) -o $@ $^ $(LDFLAGS)

microlink: $(MICROLINK_OBJS)
	$(CC) -o $@ $^ $(LDFLAGS)

microdis: $(MICRODIS_OBJS)
	$(CC) -o $@ $^ $(LDFLAGS)

.SUFFIXES: .bin .asm

.asm.bin: include/devmap.inc include/pseudo.inc
	./microasm -binary $< $@

clean:
	rm -f $(MICROASM_OBJS) $(MICROLINK_OBJS) $(MICRODIS_OBJS) $(TARGET) $(MODULES)

codestyle:
	astyle --style=kr --indent=spaces=4 --add-braces *.c

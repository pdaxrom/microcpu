TARGET = microasm

MODULES = modules/display.bin

all: $(TARGET) $(MODULES)

CFLAGS = -Wall -Wpedantic -g

LDFLAGS = -g

OBJS = microasm.o

$(TARGET): $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS)

.SUFFIXES: .bin .asm

.asm.bin: include/devmap.inc include/pseudo.inc
	./$(TARGET) -binary $< $@

clean:
	rm -f $(OBJS) $(TARGET) $(MODULES)

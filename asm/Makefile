TARGET = microasm

all: $(TARGET)

CFLAGS = -Wall -Wpedantic

OBJS = microasm.o

$(TARGET): $(OBJS)
	$(CC) -o $@ $^

clean:
	rm -f $(OBJS) $(TARGET)

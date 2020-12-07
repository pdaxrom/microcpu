TARGET = microasm

all: $(TARGET)

CFLAGS = -Wall -Wpedantic -g

LDFLAGS = -g

OBJS = microasm.o

$(TARGET): $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS)

clean:
	rm -f $(OBJS) $(TARGET)

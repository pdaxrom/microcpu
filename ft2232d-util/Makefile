TARGET = ft2232d-ctl

OBJS = ft2232d-ctl.c

$(TARGET): $(OBJS)
	$(CC) -o $@ $^ -lusb

clean:
	rm -f $(TARGET) *.o

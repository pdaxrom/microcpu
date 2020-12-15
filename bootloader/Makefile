all: bootloader ../boards/sram.mem

bootloader: bootloader.c
	$(CC) $^ -o $@ -Wall -O2 -g

../boards/sram.mem: bootldr.asm
	../asm/microasm $^ $@

clean:
	rm -f bootloader

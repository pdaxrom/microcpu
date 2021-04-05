all: bootloader ../boards/sram.mem ../boards/sram-mcu.mem

bootloader: bootloader.c
	$(CC) $^ -o $@ -Wall -O2 -g

../boards/sram.mem: bootldr.asm
	../asm/microasm $^ $@

../boards/sram-mcu.mem: bootldr-mcu.asm
	../asm/microasm $^ $@

clean:
	rm -f bootloader

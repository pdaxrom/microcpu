ASM ?= ../asm/microasm

all: bootloader ../boards/sram.mem ../boards/sram-mcu.mem

bootloader: bootloader.c
	$(CC) $^ -o $@ -Wall -O2 -g

$(ASM): ../asm/microasm.c
	$(MAKE) -C ../asm microasm

../boards/sram.mem: bootldr.asm ../asm/include/pseudo.inc ../asm/include/devmap.inc $(ASM)
	$(ASM) $< $@

../boards/sram-mcu.mem: bootldr-mcu.asm ../asm/include/pseudo.inc ../asm/include/devmap.inc $(ASM)
	$(ASM) $< $@

clean:
	rm -f bootloader ../boards/sram.mem ../boards/sram-mcu.mem

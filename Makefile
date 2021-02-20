all:
	make -C asm
	make -C bootloader
	make -C boards

clean:
	make -C asm clean
	make -C bootloader clean
	make -C boards clean

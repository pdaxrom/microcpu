.PHONY: all test clean

all:
	$(MAKE) -C asm
	$(MAKE) -C bootloader
	$(MAKE) -C boards

test:
	$(MAKE) -C testbench test

clean:
	$(MAKE) -C asm clean
	$(MAKE) -C bootloader clean
	$(MAKE) -C boards clean
	$(MAKE) -C testbench clean

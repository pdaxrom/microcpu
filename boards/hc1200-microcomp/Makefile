# Default board firmware: J-11 + FIS + 50-Hz clock + SD power-on bootstrap.
# This preparation step is portable and does not invoke Diamond.
.PHONY: all diamond original diag diag-diamond
all:
	$(MAKE) -C .. hc1200-microcomp
diamond:
	$(MAKE) -C .. hc1200-microcomp-diamond
# Legacy firmware/SCUBA RAM generation for microcomp-original.ldf.
original:
	$(MAKE) -C ../../bootloader ../boards/sram.mem
	$(MAKE) -C .. hc1200-microcomp-original

# Native UART/SD/FRAM diagnostics, separate project and generated images.
diag:
	$(MAKE) -C .. hc1200-diag
diag-diamond:
	$(MAKE) -C .. hc1200-diag-diamond

# Shared SD image rules; included by the main boards Makefile.
SD_DEPS = $(wildcard ../ucode/v2/*.asm ../ucode/v2/*.inc) ../ucode/experimental/rh11_sd.asm
SD_BIN = hc1200-microcomp/j11_sd.bin
SD_NOFIS_BIN = hc1200-microcomp/j11_sd_nofis.bin
.PHONY: disk-ucode disk-diamond disk-nofis-ucode disk-nofis-diamond

$(SD_BIN): $(SD_DEPS) $(MICROASM) sd.mk ../ucode/config.mk
	$(MICROASM) --cpu ucode -D J11_DISK_PROTOTYPE -D J11_SD_AUTOBOOT -binary ../ucode/v2/j11.asm $@
$(SD_NOFIS_BIN): $(SD_DEPS) $(MICROASM) sd.mk ../ucode/config.mk
	$(MICROASM) --cpu ucode -D J11_DISK_PROTOTYPE -D J11_SD_AUTOBOOT -D J11_DISABLE_FIS -binary ../ucode/v2/j11.asm $@
hc1200-microcomp/j11_sd.mem: $(SD_BIN) ../ucode/make_urom_ebr.py ../ucode/config.mk sd.mk
	$(PYTHON) ../ucode/make_urom_ebr.py $< --words $(J11_UROM_WORDS) --format mem > $@
hc1200-microcomp/j11_sd_nofis.mem: $(SD_NOFIS_BIN) ../ucode/make_urom_ebr.py ../ucode/config.mk sd.mk
	$(PYTHON) ../ucode/make_urom_ebr.py $< --words $(J11_UROM_WORDS) --format mem > $@
hc1200-microcomp/sd_urom_ebr.v: $(SD_BIN) ../ucode/make_urom_ebr.py ../ucode/config.mk sd.mk
	$(PYTHON) ../ucode/make_urom_ebr.py $< --words $(J11_UROM_WORDS) --module-name ucode_urom_ebr > $@
hc1200-microcomp/sd_nofis_urom_ebr.v: $(SD_NOFIS_BIN) ../ucode/make_urom_ebr.py ../ucode/config.mk sd.mk
	$(PYTHON) ../ucode/make_urom_ebr.py $< --words $(J11_UROM_WORDS) --module-name ucode_urom_ebr > $@
disk-ucode: hc1200-microcomp/j11_sd.mem hc1200-microcomp/sd_urom_ebr.v
disk-diamond: disk-ucode
	cd hc1200-microcomp && LD_PRELOAD="$(DIAMOND_LIBSTDCPP)" "$(DIAMOND_HOME)/bin/lin64/diamondc" build-sd.tcl
disk-nofis-ucode: hc1200-microcomp/j11_sd_nofis.mem hc1200-microcomp/sd_nofis_urom_ebr.v
disk-nofis-diamond: disk-nofis-ucode
	cd hc1200-microcomp && LD_PRELOAD="$(DIAMOND_LIBSTDCPP)" "$(DIAMOND_HOME)/bin/lin64/diamondc" build-sd-nofis.tcl

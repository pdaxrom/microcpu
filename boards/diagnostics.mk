# Independent native diagnostic image. Never overwrite the SD/J-11 images.
DIAG_ASM = ../ucode/diagnostics/sd_fram.asm
DIAG_BIN = hc1200-microcomp/sd_fram_diag.bin
DIAG_MEM = hc1200-microcomp/sd_fram_diag.mem
DIAG_EBR = hc1200-microcomp/sd_fram_diag_ebr.v
.PHONY: hc1200-diag hc1200-diag-diamond

$(DIAG_BIN): $(DIAG_ASM) ../ucode/v2/pseudo.inc $(MICROASM) diagnostics.mk
	$(MICROASM) --cpu ucode --list hc1200-microcomp/sd_fram_diag.lst -binary $< $@
$(DIAG_MEM): $(DIAG_BIN) ../ucode/make_urom_ebr.py ../ucode/config.mk diagnostics.mk
	$(PYTHON) ../ucode/make_urom_ebr.py $< --words $(J11_UROM_WORDS) --format mem > $@
$(DIAG_EBR): $(DIAG_BIN) ../ucode/make_urom_ebr.py ../ucode/config.mk diagnostics.mk
	$(PYTHON) ../ucode/make_urom_ebr.py $< --words $(J11_UROM_WORDS) --module-name ucode_urom_ebr > $@
hc1200-diag: $(DIAG_MEM) $(DIAG_EBR)
hc1200-diag-diamond: hc1200-diag
	cd hc1200-microcomp && LD_PRELOAD="$(DIAMOND_LIBSTDCPP)" "$(DIAMOND_HOME)/bin/lin64/diamondc" build-diag.tcl

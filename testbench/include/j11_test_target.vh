// Guest-level tests run against either engine without changing their assertions.
`ifndef J11_TEST_TARGET_VH
`define J11_TEST_TARGET_VH
`ifndef J11_ENGINE_MODULE
`define J11_ENGINE_MODULE j11_microengine
`endif
`ifndef J11_BOARD_MODULE
`define J11_BOARD_MODULE j11_hc1200_microcomp
`endif
`ifndef J11_UCODE_FILE
`define J11_UCODE_FILE "build/j11_ucode.words"
`endif
`ifndef J11_EBR_MODULE
`define J11_EBR_MODULE j11_urom_ebr
`endif
`endif

# Keep simulation and generated board images at the same depth. Architectural
# emulation lives in assembly; changing this storage size adds no RISC opcode.
J11_UROM_WORDS = 3584
# The six-bit context ABI reserves the last 64 words of that same memory.
J11_UCODE_WORDS = $(shell expr $(J11_UROM_WORDS) - 64)

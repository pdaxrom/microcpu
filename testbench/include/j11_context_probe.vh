// Test-only view of the ACTUAL context storage, not a shadow register file.
// Define J11_CONTEXT_ENGINE to the instance path before including this file.
// The vendor model stores each 18-bit location contiguously in v_MEM. Only
// this probe knows that layout; production RTL has no simulation backdoor.
wire [15:0] context_words [0:63];
genvar context_probe_index;
genvar context_probe_bit;
generate for (context_probe_index = 0; context_probe_index < 64;
	context_probe_index = context_probe_index + 1) begin : context_probe
`ifdef J11_EBR_UROM
	for (context_probe_bit = 0; context_probe_bit < 16;
		context_probe_bit = context_probe_bit + 1) begin : bits
		assign context_words[context_probe_index][context_probe_bit] =
			`J11_CONTEXT_ENGINE.microcode_rom.context_ebr.EBR_INST.v_MEM[
				(448 + context_probe_index) * 18 + context_probe_bit];
	end
`else
	assign context_words[context_probe_index] =
		`J11_CONTEXT_ENGINE.urom[`J11_CONTEXT_ENGINE.CONTEXT_BASE + context_probe_index];
`endif
end endgenerate

// Only the C fixture importer and the future-console stimulus use deposits.
// Native write/read tests exercise the actual RAM ports instead.
task deposit_context(input [5:0] index, input [15:0] value);
integer bit_index;
begin
`ifdef J11_EBR_UROM
	for (bit_index = 0; bit_index < 18; bit_index = bit_index + 1)
		`J11_CONTEXT_ENGINE.microcode_rom.context_ebr.EBR_INST.v_MEM[
			(448 + index) * 18 + bit_index] = bit_index < 16 ? value[bit_index] : 1'b0;
`else
	`J11_CONTEXT_ENGINE.urom[`J11_CONTEXT_ENGINE.CONTEXT_BASE + index] = value;
`endif
end
endtask
`undef J11_CONTEXT_ENGINE

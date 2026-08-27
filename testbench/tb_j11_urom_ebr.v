`timescale 1ns/1ps

// Exercise the actual generated PDPW8KC netlist, using Lattice's simulation
// library. Visit every word in a permuted order, including every bank edge.
module tb_j11_urom_ebr;
	reg clk = 0, rst = 1, enable = 0;
	reg [11:0] address = 0;
	wire [15:0] data;
	reg [15:0] expected [0:`J11_UROM_WORDS-1];
	reg [15:0] held;
	integer i;
	j11_urom_ebr #(.WORDS(`J11_UROM_WORDS)) dut (
		.clk(clk), .rst(rst), .enable(enable), .address(address), .data(data)
	);
	always #5 clk = !clk;
	initial begin
		for (i = 0; i < `J11_UROM_WORDS; i = i + 1) expected[i] = 16'h00b0;
		$readmemh("build/j11_ucode.words", expected);
		repeat (4) @(negedge clk);
		rst = 0;
		for (i = 0; i < `J11_UROM_WORDS; i = i + 1) begin
			@(negedge clk);
			enable = 1;
			address = (i * 769) % `J11_UROM_WORDS;
			@(posedge clk); #1;
			if (data !== expected[address])
				$fatal(1, "EBR word %0d: %04h != %04h", address, data, expected[address]);
			held = data;
			@(negedge clk);
			enable = 0;
			address = (address + 513) % `J11_UROM_WORDS;
			@(posedge clk); #1;
			if (data !== held) $fatal(1, "EBR changed with clock enable off");
		end
		$display("PASS: all %0d EBR uROM words, bank boundaries and clock enable", `J11_UROM_WORDS);
		$finish;
	end
endmodule

`timescale 1ns/1ps

// Exercise the generated PDPW8KC read AND write ports with Lattice's model.
// No deposits: verify code integrity after writes to every context location.
module tb_j11_urom_ebr;
	reg clk = 0, rst = 1, enable = 0;
	reg [11:0] address = 0;
	reg write_enable = 0;
	reg [5:0] write_address = 0;
	reg [15:0] write_data = 0;
	wire [15:0] data;
	localparam integer CONTEXT_BASE = `J11_UROM_WORDS - 64;
	reg [15:0] expected [0:`J11_UROM_WORDS-1];
	reg [15:0] held;
	integer i, pass;
	j11_urom_ebr #(.WORDS(`J11_UROM_WORDS)) dut (
		.clk(clk), .rst(rst), .enable(enable), .address(address), .data(data),
		.write_enable(write_enable), .write_address(write_address), .write_data(write_data)
	);
	always #5 clk = !clk;
	task check_all_words;
	begin
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
	end
	endtask
	initial begin
		$readmemh("build/j11_ucode.words", expected);
		repeat (4) @(negedge clk);
		rst = 0;
		check_all_words();
		for (pass = 0; pass < 18; pass = pass + 1) begin
			for (i = 0; i < 64; i = i + 1) begin
				@(negedge clk);
				enable = pass & 1;
				// Simultaneous read from code, write into context in the same EBR.
				address = CONTEXT_BASE - 1 - i;
				write_enable = 1;
				write_address = i;
				write_data = pass == 17 ? 16'hffff : (16'h0001 << pass) ^ (i * 257);
				held = data;
				@(posedge clk); #1;
				if (data !== (enable ? expected[address] : held))
					$fatal(1, "Context write disturbed code read/output hold");
				expected[CONTEXT_BASE + i] = write_data;
				@(negedge clk);
				write_enable = 0;
				write_data = ~write_data; // must not be stored with write enable off
				enable = 1;
				address = CONTEXT_BASE + i;
				@(posedge clk); #1;
				if (data !== expected[address])
					$fatal(1, "EBR context[%0d] pass %0d: %04h != %04h", i, pass, data, expected[address]);
			end
		end
		// Primitive reset must not erase code or context; the engine explicitly
		// clears only context on restart. Writes during reset are suppressed.
		@(negedge clk);
		rst = 1;
		write_enable = 1;
		write_data = 16'h5aa5;
		for (i = 0; i < 64; i = i + 1) begin
			write_address = i;
			@(negedge clk);
		end
		write_enable = 0;
		rst = 0;
		check_all_words();
		$display("PASS: all %0d EBR words, 1152 context writes/readbacks, code integrity, reset and port enables", `J11_UROM_WORDS);
		$finish;
	end
endmodule

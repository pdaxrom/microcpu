`timescale 1ns/1ps
module tb_spi_byte_service;
	reg clk = 0, rst = 1, req = 0, wr = 0, byte_access = 0;
	reg [1:0] address = 0;
	reg [15:0] wdata = 0;
	wire [15:0] rdata;
	wire ready, error, busy, cs_n, sck, mosi;
	integer i, fast, edges = 0, completions = 0, start_edges, delay_cycles;
	spi_byte_service #(.SLOW_DIV(3), .FAST_DIV(1)) dut (
		.clk(clk), .rst(rst), .req(req), .write(wr), .byte_access(byte_access),
		.address(address), .wdata(wdata), .rdata(rdata), .ready(ready),
		.error(error), .busy(busy), .cs_n(cs_n), .sck(sck), .mosi(mosi), .miso(!mosi)
	);
	always #5 clk = !clk;
	always @(posedge sck) edges = edges + 1;
	always @(negedge clk) if (ready) completions = completions + 1;
	task transfer;
		input write_value, byte_value;
		input [1:0] address_value;
		input [15:0] data_value, expected;
		input want_error;
		integer previous_completions;
		begin
			@(negedge clk);
			req = 1; wr = write_value; byte_access = byte_value;
			address = address_value; wdata = data_value;
			delay_cycles = 0;
			while (!ready) begin
				@(negedge clk); delay_cycles = delay_cycles + 1;
				if (delay_cycles > 60) $fatal(1, "SPI byte timeout");
			end
			if (rdata !== expected || error !== want_error || busy || sck)
				$fatal(1, "SPI response data=%h expected=%h error=%b/%b", rdata, expected, error, want_error);
			@(negedge clk); previous_completions = completions;
			repeat (4) @(negedge clk);
			if (completions != previous_completions || busy) $fatal(1, "Held request repeated");
			req = 0; repeat (2) @(negedge clk);
		end
	endtask
	initial begin
		repeat (3) @(negedge clk); rst = 0;
		if (!cs_n || sck || !mosi) $fatal(1, "Unsafe reset pins");
		for (fast = 0; fast < 2; fast = fast + 1) begin
			transfer(1, 0, 2, fast * 2, fast ? 0 : 1, 0);
			for (i = 0; i < 256; i = i + 1) begin
				start_edges = edges;
				transfer(1, 0, 0, i, (i ^ 255), 0);
				if (edges - start_edges != 8 || cs_n ||
						delay_cycles != (fast ? 17 : 49)) $fatal(1, "SPI clock count/divider");
			end
		end
		transfer(0, 0, 0, 0, 0, 0); // read clocks FF
		start_edges = edges;
		transfer(1, 1, 1, 0, 0, 0); // high lane is inert
		transfer(1, 0, 1, 0, 0, 1); // misaligned word
		if (edges != start_edges) $fatal(1, "Invalid access clocked device");
		@(negedge clk); req = 1; wr = 1; address = 0;
		repeat (4) @(negedge clk); rst = 1;
		repeat (2) @(negedge clk);
		if (busy || ready || sck || !cs_n) $fatal(1, "Reset did not abort transfer");
		$display("PASS: SPI bytes 512 values/speeds, read, held request, alignment, reset");
		$finish;
	end
endmodule

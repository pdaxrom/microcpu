`timescale 1ns/1ps

module tb_spi_fram_guest_ram #(parameter integer CLK_DIV = 1);
	reg clk;
	reg rst;
	reg req;
	reg write;
	reg byte_access;
	reg bank;
	reg [15:0] address;
	reg [15:0] wdata;
	wire [15:0] rdata;
	wire ready;
	wire error;
	wire busy;
	wire spi_cs_n;
	wire spi_sck;
	wire spi_mosi;
	wire spi_miso;
	integer old_transactions;
	integer cycle = 0, last_edge = 0;
	reg previous_sck = 0;

	spi_fram_guest_ram #(
		.CLK_DIV(CLK_DIV)
	) dut (
		.clk(clk),
		.rst(rst),
		.req(req),
		.write(write),
		.byte_access(byte_access),
		.bank(bank),
		.address(address),
		.wdata(wdata),
		.rdata(rdata),
		.ready(ready),
		.error(error),
		.busy(busy),
		.spi_cs_n(spi_cs_n),
		.spi_sck(spi_sck),
		.spi_mosi(spi_mosi),
		.spi_miso(spi_miso)
	);

	spi_fram_model fram (
		.cs_n(spi_cs_n),
		.sck(spi_sck),
		.mosi(spi_mosi),
		.miso(spi_miso)
	);

	always #5 clk = !clk;
	// Check every high phase and every intra-byte low phase. The low gap
	// between bytes intentionally includes command-state overhead.
	always @(negedge clk) begin
		cycle = cycle + 1;
		if (!rst && spi_sck != previous_sck) begin
			if ((!spi_sck || dut.bit_count != 0) && cycle - last_edge != CLK_DIV)
				$fatal(1, "SPI divider %0d: half-cycle was %0d clocks", CLK_DIV, cycle - last_edge);
			last_edge = cycle;
		end
		previous_sck = spi_sck;
	end

	task request_write;
		input req_bank;
		input req_byte;
		input [15:0] req_address;
		input [15:0] req_data;
		begin
			@(negedge clk);
			bank = req_bank;
			byte_access = req_byte;
			address = req_address;
			wdata = req_data;
			write = 1;
			req = 1;
			while (!ready) @(negedge clk);
			if (error) begin
				$display("FAIL: unexpected write error at %04x", req_address);
				$finish_and_return(1);
			end
			req = 0;
			@(negedge clk);
		end
	endtask

	task request_read;
		input req_bank;
		input req_byte;
		input [15:0] req_address;
		input [15:0] expected;
		begin
			@(negedge clk);
			bank = req_bank;
			byte_access = req_byte;
			address = req_address;
			wdata = 0;
			write = 0;
			req = 1;
			while (!ready) @(negedge clk);
			if (error || rdata !== expected) begin
				$display("FAIL: read bank=%0d addr=%04x got=%04x expected=%04x error=%0d",
					bank, req_address, rdata, expected, error);
				$finish_and_return(1);
			end
			req = 0;
			@(negedge clk);
		end
	endtask

	initial begin
		clk = 0;
		rst = 1;
		req = 0;
		write = 0;
		byte_access = 0;
		bank = 0;
		address = 0;
		wdata = 0;

		repeat (4) @(negedge clk);
		rst = 0;

		request_write(0, 1, 16'h1234, 16'h00a5);
		request_write(1, 1, 16'h1234, 16'h005a);
		if (fram.memory[17'h01234] !== 8'ha5 ||
				fram.memory[17'h11234] !== 8'h5a) begin
			$display("FAIL: banked byte writes bank0=%02x bank1=%02x",
				fram.memory[17'h01234], fram.memory[17'h11234]);
			$finish_and_return(1);
		end
		request_read(0, 1, 16'h1234, 16'h00a5);
		request_read(1, 1, 16'h1234, 16'h005a);

		request_write(0, 0, 16'h3456, 16'habcd);
		if (fram.memory[17'h03456] !== 8'hcd ||
				fram.memory[17'h03457] !== 8'hab) begin
			$display("FAIL: word write is not little endian");
			$finish_and_return(1);
		end
		request_read(0, 0, 16'h3456, 16'habcd);

		old_transactions = fram.transaction_count;
		@(negedge clk);
		bank = 0;
		byte_access = 0;
		address = 16'h3457;
		write = 0;
		req = 1;
		while (!ready) @(negedge clk);
		if (!error || fram.transaction_count != old_transactions) begin
			$display("FAIL: odd word access did not fail locally");
			$finish_and_return(1);
		end
		req = 0;

		$display("PASS: SPI FRAM divider=%0d, clock phases, byte/word/bank/odd-address", CLK_DIV);
		$finish_and_return(0);
	end

	initial begin
		#(200000 * CLK_DIV);
		$display("FAIL: timeout");
		$finish_and_return(1);
	end

endmodule

`timescale 1ns/1ps

module tb_j11_guest_bus;
	reg clk;
	reg rst;
	reg guest_reset;
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
	reg uart_rx;
	wire uart_tx;
	wire irq;
	wire [2:0] irq_level;
	wire [7:0] irq_vector;
	wire spi_cs_n;
	wire spi_sck;
	wire spi_mosi;
	wire spi_miso;
	integer old_transactions;

	j11_hc1200_guest_bus #(
		.FRAM_CLK_DIV(1)
	) dut (
		.clk(clk),
		.rst(rst),
		.guest_reset(guest_reset),
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
		.uart_rx(uart_rx),
		.uart_tx(uart_tx),
		.irq(irq),
		.irq_level(irq_level),
		.irq_vector(irq_vector),
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

	task bus_write;
		input req_bank;
		input req_byte;
		input [15:0] req_address;
		input [15:0] req_data;
		input expected_error;
		begin
			@(negedge clk);
			bank = req_bank;
			byte_access = req_byte;
			address = req_address;
			wdata = req_data;
			write = 1;
			req = 1;
			while (!ready) @(negedge clk);
			if (error !== expected_error) begin
				$display("FAIL: bus write addr=%04x error=%0d expected=%0d",
					req_address, error, expected_error);
				$finish_and_return(1);
			end
			req = 0;
			@(negedge clk);
		end
	endtask

	task bus_read;
		input req_bank;
		input req_byte;
		input [15:0] req_address;
		input [15:0] expected_data;
		input expected_error;
		begin
			@(negedge clk);
			bank = req_bank;
			byte_access = req_byte;
			address = req_address;
			wdata = 0;
			write = 0;
			req = 1;
			while (!ready) @(negedge clk);
			if (error !== expected_error ||
					(!expected_error && rdata !== expected_data)) begin
				$display("FAIL: bus read addr=%04x data=%04x expected=%04x error=%0d",
					req_address, rdata, expected_data, error);
				$finish_and_return(1);
			end
			req = 0;
			@(negedge clk);
		end
	endtask

	initial begin
		clk = 0;
		rst = 1;
		guest_reset = 0;
		req = 0;
		write = 0;
		byte_access = 0;
		bank = 0;
		address = 0;
		wdata = 0;
		uart_rx = 1;

		repeat (4) @(negedge clk);
		rst = 0;

		bus_write(0, 0, 16'h2000, 16'h55aa, 0);
		bus_read(0, 0, 16'h2000, 16'h55aa, 0);

		old_transactions = fram.transaction_count;
		bus_read(0, 0, 16'hff74, 16'h0080, 0);
		if (fram.transaction_count != old_transactions) begin
			$display("FAIL: DL11 access leaked into FRAM");
			$finish_and_return(1);
		end

		bus_write(0, 1, 16'hff74, 16'h0040, 0);
		if (!irq || irq_level !== 3'd4 || irq_vector !== 8'o64) begin
			$display("FAIL: DL11 TX ready interrupt irq=%0d level=%0d vector=%03o",
				irq, irq_level, irq_vector);
			$finish_and_return(1);
		end
		guest_reset = 1;
		@(negedge clk);
		guest_reset = 0;
		@(negedge clk);
		if (irq || dut.rx_ie !== 0 || dut.tx_ie !== 0) begin
			$display("FAIL: guest RESET did not clear DL11 interrupt enables");
			$finish_and_return(1);
		end
		bus_write(0, 1, 16'hff74, 16'h0040, 0);

		bus_write(0, 1, 16'hff76, 16'h0041, 0);
		if (uart_tx !== 0 || irq) begin
			$display("FAIL: DL11 TBUF did not start UART transmission");
			$finish_and_return(1);
		end
		while (!irq) @(negedge clk);
		if (irq_vector !== 8'o64) begin
			$display("FAIL: DL11 TX completion vector=%03o", irq_vector);
			$finish_and_return(1);
		end
		bus_write(0, 1, 16'hff74, 16'h0000, 0);

		old_transactions = fram.transaction_count;
		bus_read(0, 0, 16'he000, 16'h0000, 1);
		bus_read(0, 0, 16'hff71, 16'h0000, 1);
		if (fram.transaction_count != old_transactions) begin
			$display("FAIL: invalid I/O-page access leaked into FRAM");
			$finish_and_return(1);
		end

		bus_write(1, 1, 16'he000, 16'h00a5, 0);
		bus_read(1, 1, 16'he000, 16'h00a5, 0);

		$display("PASS: HC1200 guest bus FRAM overlay and DL11 console");
		$finish_and_return(0);
	end

	initial begin
		#300000;
		$display("FAIL: HC1200 guest bus timeout");
		$finish_and_return(1);
	end

endmodule

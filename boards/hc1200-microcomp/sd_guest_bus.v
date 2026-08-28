`timescale 1ns/1ps

// Experimental native services. Guest RK registers belong to microcode.
// F008 SPI byte; F00A SPI control; F00C FRAM bank override (bit 0).
// The single microengine serializes guest and disk DMA requests; there is
// no second master or hidden transaction which can race the FRAM port.
module ucode_sd_guest_bus #(
	parameter integer FRAM_CLK_DIV = 2,
	parameter integer TICK_DIVISOR = 443333,
	parameter integer SD_SLOW_DIV = 68,
	parameter integer SD_FAST_DIV = 2
) (
	input wire clk, rst, guest_reset,
	input wire req, write, byte_access, bank,
	input wire [15:0] address, wdata,
	output wire [15:0] rdata,
	output wire ready, error, busy,
	input wire uart_rx,
	output wire uart_tx,
	output wire irq,
	output wire [2:0] irq_level,
	output wire [7:0] irq_vector,
	output wire spi_cs_n, spi_sck, spi_mosi,
	input wire spi_miso,
	output wire sd_cs_n, sd_sck, sd_mosi,
	input wire sd_miso
);
	wire selected = address[15:3] == 13'h1e01;
	wire [15:0] base_data, spi_data;
	wire base_ready, base_error, base_busy, spi_ready, spi_error, spi_busy;
	reg bank_override, bank_ready, bank_error, bank_seen;
	reg [15:0] bank_data;
	j11_hc1200_guest_bus #(.FRAM_CLK_DIV(FRAM_CLK_DIV), .TICK_DIVISOR(TICK_DIVISOR)) base (
		.clk(clk), .rst(rst), .guest_reset(guest_reset), .req(req && !selected),
		.write(write), .byte_access(byte_access), .bank(bank || bank_override),
		.address(address), .wdata(wdata), .rdata(base_data),
		.ready(base_ready), .error(base_error), .busy(base_busy),
		.uart_rx(uart_rx), .uart_tx(uart_tx), .irq(irq), .irq_level(irq_level), .irq_vector(irq_vector),
		.spi_cs_n(spi_cs_n), .spi_sck(spi_sck), .spi_mosi(spi_mosi), .spi_miso(spi_miso)
	);
	spi_byte_service #(.SLOW_DIV(SD_SLOW_DIV), .FAST_DIV(SD_FAST_DIV)) spi (
		.clk(clk), .rst(rst || guest_reset), .req(req && selected && !address[2]),
		.write(write), .byte_access(byte_access), .address(address[1:0]), .wdata(wdata),
		.rdata(spi_data), .ready(spi_ready), .error(spi_error), .busy(spi_busy),
		.cs_n(sd_cs_n), .sck(sd_sck), .mosi(sd_mosi), .miso(sd_miso)
	);
	assign rdata = !selected ? base_data : address[2] ? bank_data : spi_data;
	assign ready = !selected ? base_ready : address[2] ? bank_ready : spi_ready;
	assign error = !selected ? base_error : address[2] ? bank_error : spi_error;
	assign busy = base_busy || spi_busy;
	always @(posedge clk) begin
		if (rst || guest_reset) begin
			bank_override <= 0; bank_ready <= 0; bank_error <= 0; bank_seen <= 0; bank_data <= 0;
		end else begin
			bank_ready <= 0; bank_error <= 0;
			if (!req) bank_seen <= 0;
			if (req && selected && address[2] && !bank_seen) begin
				bank_seen <= 1; bank_ready <= 1; bank_data <= 0;
				if (address[1] || (!byte_access && address[0])) bank_error <= 1;
				else if (!address[0]) begin
					bank_data <= {15'b0, bank_override};
					if (write) bank_override <= wdata[0];
				end
			end
		end
	end
endmodule

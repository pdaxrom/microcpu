`timescale 1ns/1ps

// Generic mode-0 byte service, not an SD/RK controller. A data write clocks
// wdata[7:0]; a data read clocks FF. Completion returns the received byte.
// Control bit 0 = CS_n, bit 1 = fast clock. No sector RAM or guest registers.
module spi_byte_service #(
	parameter integer SLOW_DIV = 68,
	parameter integer FAST_DIV = 2
) (
	input wire clk, rst, req, write, byte_access,
	input wire [1:0] address,
	input wire [15:0] wdata,
	output reg [15:0] rdata,
	output reg ready, error,
	output reg busy,
	output wire cs_n, mosi,
	output reg sck,
	input wire miso
);
	localparam integer DIV_WIDTH = SLOW_DIV > FAST_DIV ?
		$clog2(SLOW_DIV + 1) : $clog2(FAST_DIV + 1);
	reg [DIV_WIDTH-1:0] divider;
	reg [1:0] control;
	reg [7:0] tx_shift, rx_shift;
	reg [2:0] bit_count;
	reg seen;
	wire [DIV_WIDTH-1:0] limit = control[1] ? FAST_DIV - 1 : SLOW_DIV - 1;
	assign cs_n = control[0];
	assign mosi = busy ? tx_shift[7] : 1'b1;

	always @(posedge clk) begin
		if (rst) begin
			control <= 1; divider <= 0; bit_count <= 0;
			tx_shift <= 8'hff; rx_shift <= 0; rdata <= 0;
			ready <= 0; error <= 0; busy <= 0; sck <= 0; seen <= 0;
		end else begin
			ready <= 0; error <= 0;
			if (!req) seen <= 0;
			if (busy) begin
				if (divider == limit) begin
					divider <= 0;
					sck <= !sck;
					if (!sck) rx_shift <= {rx_shift[6:0], miso};
					else if (bit_count == 7) begin
						busy <= 0; ready <= 1; rdata <= {8'b0, rx_shift};
					end else begin
						tx_shift <= {tx_shift[6:0], 1'b1};
						bit_count <= bit_count + 1'b1;
					end
				end else divider <= divider + 1'b1;
			end else if (req && !seen) begin
				seen <= 1; rdata <= 0;
				if (address[0]) begin
					ready <= 1; error <= !byte_access;
				end else if (address[1]) begin
				ready <= 1; rdata <= {14'b0, control};
				if (write) control <= wdata[1:0];
			end else begin
				busy <= 1; bit_count <= 0; divider <= 0; sck <= 0;
				tx_shift <= write ? wdata[7:0] : 8'hff;
			end
			end
		end
	end
endmodule

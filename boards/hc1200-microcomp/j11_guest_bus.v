`timescale 1ns/1ps

module j11_hc1200_guest_bus #(
	parameter integer FRAM_CLK_DIV = 2
) (
	input  wire        clk,
	input  wire        rst,
	input  wire        guest_reset,

	input  wire        req,
	input  wire        write,
	input  wire        byte_access,
	input  wire        bank,
	input  wire [15:0] address,
	input  wire [15:0] wdata,
	output wire [15:0] rdata,
	output wire        ready,
	output wire        error,
	output wire        busy,

	input  wire        uart_rx,
	output wire        uart_tx,
	output wire        irq,
	output wire [2:0]  irq_level,
	output wire [7:0]  irq_vector,

	output wire        spi_cs_n,
	output wire        spi_sck,
	output wire        spi_mosi,
	input  wire        spi_miso
);

	wire io_page = !bank && address[15:13] == 3'b111;
	wire dl11_selected = io_page && address[15:3] == 13'h1fee;
	wire fram_selected = bank || !io_page;
	wire odd_word = !byte_access && address[0];

	wire [15:0] fram_rdata;
	wire fram_ready;
	wire fram_error;
	wire fram_busy;

	reg [15:0] io_rdata;
	reg io_ready;
	reg io_error;
	reg io_request_seen;

	reg rx_ie;
	reg tx_ie;
	reg uart_cs;
	reg uart_clear_rx;

	wire uart_a0 = address[1];
	wire uart_rnw = uart_clear_rx || !write;
	wire [7:0] uart_dout;
	wire uart_rx_ready;
	wire uart_tx_ready;
	wire access_low_byte = !byte_access || !address[0];

	spi_fram_guest_ram #(
		.CLK_DIV(FRAM_CLK_DIV)
	) fram (
		.clk(clk),
		.rst(rst),
		.req(req && fram_selected),
		.write(write),
		.byte_access(byte_access),
		.bank(bank),
		.address(address),
		.wdata(wdata),
		.rdata(fram_rdata),
		.ready(fram_ready),
		.error(fram_error),
		.busy(fram_busy),
		.spi_cs_n(spi_cs_n),
		.spi_sck(spi_sck),
		.spi_mosi(spi_mosi),
		.spi_miso(spi_miso)
	);

	uart console (
		.clk(clk),
		.reset(rst || guest_reset),
		.a0(uart_a0),
		.din(wdata[7:0]),
		.dout(uart_dout),
		.rnw(uart_rnw),
		.cs(uart_cs),
		.rxd(uart_rx),
		.txd(uart_tx),
		.rx_ready(uart_rx_ready),
		.tx_ready(uart_tx_ready)
	);

	assign rdata = fram_selected ? fram_rdata : io_rdata;
	assign ready = fram_selected ? fram_ready : io_ready;
	assign error = fram_selected ? fram_error : io_error;
	assign busy = fram_busy || (req && io_page && !io_ready);

	assign irq = (rx_ie && uart_rx_ready) || (tx_ie && uart_tx_ready);
	assign irq_level = 3'd4;
	assign irq_vector = (rx_ie && uart_rx_ready) ? 8'o60 : 8'o64;

	always @(posedge clk) begin
		if (rst || guest_reset) begin
			io_rdata <= 0;
			io_ready <= 0;
			io_error <= 0;
			io_request_seen <= 0;
			rx_ie <= 0;
			tx_ie <= 0;
			uart_cs <= 0;
			uart_clear_rx <= 0;
		end else begin
			io_ready <= 0;
			io_error <= 0;
			uart_cs <= 0;
			uart_clear_rx <= 0;

			if (!req) begin
				io_request_seen <= 0;
			end

			if (req && io_page && !io_request_seen) begin
				io_request_seen <= 1;
				io_rdata <= 0;
				io_ready <= 1;

				if (odd_word) begin
					io_error <= 1;
				end else if (!dl11_selected) begin
					io_error <= 1;
				end else begin
					case (address[2:1])
					2'd0: begin
						if (!write && access_low_byte) begin
							io_rdata <= {8'b0, uart_rx_ready, rx_ie, 6'b0};
						end else if (write && access_low_byte) begin
							rx_ie <= wdata[6];
							if (wdata[0]) begin
								uart_cs <= 1;
								uart_clear_rx <= 1;
							end
						end
					end
					2'd1: begin
						if (!write && access_low_byte) begin
							io_rdata <= {8'b0, uart_dout};
							uart_cs <= 1;
							uart_clear_rx <= 1;
						end else if (write && access_low_byte) begin
							uart_cs <= 1;
							uart_clear_rx <= 1;
						end
					end
					2'd2: begin
						if (!write && access_low_byte) begin
							io_rdata <= {8'b0, uart_tx_ready, tx_ie, 6'b0};
						end else if (write && access_low_byte) begin
							tx_ie <= wdata[6];
						end
					end
					2'd3: begin
						if (write && access_low_byte) begin
							uart_cs <= 1;
						end
					end
					default: begin
						io_error <= 1;
					end
					endcase
				end
			end
		end
	end

endmodule

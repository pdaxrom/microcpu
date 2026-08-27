`timescale 1ns/1ps

module spi_fram_guest_ram #(
	parameter integer CLK_DIV = 1
) (
	input  wire        clk,
	input  wire        rst,

	input  wire        req,
	input  wire        write,
	input  wire        byte_access,
	input  wire        bank,
	input  wire [15:0] address,
	input  wire [15:0] wdata,
	output reg  [15:0] rdata,
	output reg         ready,
	output reg         error,
	output wire        busy,

	output reg         spi_cs_n,
	output reg         spi_sck,
	output reg         spi_mosi,
	input  wire        spi_miso
);

	localparam [7:0] CMD_WREN  = 8'h06;
	localparam [7:0] CMD_READ  = 8'h03;
	localparam [7:0] CMD_WRITE = 8'h02;

	localparam [4:0] ST_IDLE          = 5'd0;
	localparam [4:0] ST_WREN_CMD      = 5'd1;
	localparam [4:0] ST_WREN_END      = 5'd2;
	localparam [4:0] ST_WRITE_CMD     = 5'd3;
	localparam [4:0] ST_WRITE_ADDR_HI = 5'd4;
	localparam [4:0] ST_WRITE_ADDR_MD = 5'd5;
	localparam [4:0] ST_WRITE_ADDR_LO = 5'd6;
	localparam [4:0] ST_WRITE_DATA_LO = 5'd7;
	localparam [4:0] ST_WRITE_DATA_HI = 5'd8;
	localparam [4:0] ST_WRITE_END     = 5'd9;
	localparam [4:0] ST_READ_CMD      = 5'd10;
	localparam [4:0] ST_READ_ADDR_HI  = 5'd11;
	localparam [4:0] ST_READ_ADDR_MD  = 5'd12;
	localparam [4:0] ST_READ_ADDR_LO  = 5'd13;
	localparam [4:0] ST_READ_DATA_LO  = 5'd14;
	localparam [4:0] ST_READ_SAVE_LO  = 5'd15;
	localparam [4:0] ST_READ_SAVE_HI  = 5'd16;
	localparam [4:0] ST_READ_END      = 5'd17;

	reg [4:0] state;
	reg       request_seen;
	reg       latched_byte;
	reg       latched_bank;
	reg [15:0] latched_address;
	reg [15:0] latched_wdata;

	reg       spi_active;
	reg [7:0] tx_shift;
	reg [7:0] rx_shift;
	reg [2:0] bit_count;
	integer   div_count;

	assign busy = (state != ST_IDLE) || spi_active;

	task start_spi_byte;
		input [7:0] value;
		begin
			tx_shift <= value;
			rx_shift <= 0;
			bit_count <= 0;
			div_count <= 0;
			spi_sck <= 0;
			spi_mosi <= value[7];
			spi_active <= 1;
		end
	endtask

	always @(posedge clk) begin
		if (rst) begin
			state <= ST_IDLE;
			request_seen <= 0;
			latched_byte <= 0;
			latched_bank <= 0;
			latched_address <= 0;
			latched_wdata <= 0;
			rdata <= 0;
			ready <= 0;
			error <= 0;
			spi_cs_n <= 1;
			spi_sck <= 0;
			spi_mosi <= 0;
			spi_active <= 0;
			tx_shift <= 0;
			rx_shift <= 0;
			bit_count <= 0;
			div_count <= 0;
		end else begin
			ready <= 0;
			error <= 0;

			if (!req) begin
				request_seen <= 0;
			end

			if (spi_active) begin
				if (div_count == CLK_DIV - 1) begin
					div_count <= 0;
					if (!spi_sck) begin
						spi_sck <= 1;
						rx_shift <= {rx_shift[6:0], spi_miso};
					end else begin
						spi_sck <= 0;
						if (bit_count == 3'd7) begin
							spi_active <= 0;
						end else begin
							bit_count <= bit_count + 1'b1;
							tx_shift <= {tx_shift[6:0], 1'b0};
							spi_mosi <= tx_shift[6];
						end
					end
				end else begin
					div_count <= div_count + 1;
				end
			end else begin
				case (state)
				ST_IDLE: begin
					spi_cs_n <= 1;
					spi_sck <= 0;
					if (req && !request_seen) begin
						request_seen <= 1;
						latched_byte <= byte_access;
						latched_bank <= bank;
						latched_address <= address;
						latched_wdata <= wdata;
						if (!byte_access && address[0]) begin
							ready <= 1;
							error <= 1;
						end else if (write) begin
							state <= ST_WREN_CMD;
						end else begin
							state <= ST_READ_CMD;
						end
					end
				end

				ST_WREN_CMD: begin
					spi_cs_n <= 0;
					start_spi_byte(CMD_WREN);
					state <= ST_WREN_END;
				end
				ST_WREN_END: begin
					spi_cs_n <= 1;
					state <= ST_WRITE_CMD;
				end
				ST_WRITE_CMD: begin
					spi_cs_n <= 0;
					start_spi_byte(CMD_WRITE);
					state <= ST_WRITE_ADDR_HI;
				end
				ST_WRITE_ADDR_HI: begin
					start_spi_byte({7'b0, latched_bank});
					state <= ST_WRITE_ADDR_MD;
				end
				ST_WRITE_ADDR_MD: begin
					start_spi_byte(latched_address[15:8]);
					state <= ST_WRITE_ADDR_LO;
				end
				ST_WRITE_ADDR_LO: begin
					start_spi_byte(latched_address[7:0]);
					state <= ST_WRITE_DATA_LO;
				end
				ST_WRITE_DATA_LO: begin
					start_spi_byte(latched_wdata[7:0]);
					state <= latched_byte ? ST_WRITE_END : ST_WRITE_DATA_HI;
				end
				ST_WRITE_DATA_HI: begin
					start_spi_byte(latched_wdata[15:8]);
					state <= ST_WRITE_END;
				end
				ST_WRITE_END: begin
					spi_cs_n <= 1;
					ready <= 1;
					state <= ST_IDLE;
				end

				ST_READ_CMD: begin
					spi_cs_n <= 0;
					start_spi_byte(CMD_READ);
					state <= ST_READ_ADDR_HI;
				end
				ST_READ_ADDR_HI: begin
					start_spi_byte({7'b0, latched_bank});
					state <= ST_READ_ADDR_MD;
				end
				ST_READ_ADDR_MD: begin
					start_spi_byte(latched_address[15:8]);
					state <= ST_READ_ADDR_LO;
				end
				ST_READ_ADDR_LO: begin
					start_spi_byte(latched_address[7:0]);
					state <= ST_READ_DATA_LO;
				end
				ST_READ_DATA_LO: begin
					start_spi_byte(8'h00);
					state <= ST_READ_SAVE_LO;
				end
				ST_READ_SAVE_LO: begin
					rdata[7:0] <= rx_shift;
					if (latched_byte) begin
						rdata[15:8] <= 0;
						state <= ST_READ_END;
					end else begin
						start_spi_byte(8'h00);
						state <= ST_READ_SAVE_HI;
					end
				end
				ST_READ_SAVE_HI: begin
					rdata[15:8] <= rx_shift;
					state <= ST_READ_END;
				end
				ST_READ_END: begin
					spi_cs_n <= 1;
					ready <= 1;
					state <= ST_IDLE;
				end

				default: begin
					spi_cs_n <= 1;
					state <= ST_IDLE;
					ready <= 1;
					error <= 1;
				end
				endcase
			end
		end
	end

endmodule

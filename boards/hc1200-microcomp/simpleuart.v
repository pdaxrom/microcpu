/*
 *  PicoSoC - A simple example SoC using PicoRV32
 *
 *  Copyright (C) 2017  Clifford Wolf <clifford@clifford.at>
 *
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

module simpleuart #(parameter integer DEFAULT_DIV = 27) (
	input wire CLK,
	input wire RESET,

	output wire ser_tx,
	input  wire ser_rx,

	input wire  ADDR,
	input wire	[7:0] DI,
	output reg	[7:0] DO,

	input wire		  CS,
	input wire		  RW
);
	reg [15:0] cfg_divider;

	reg  [7:0] reg_dat_di;
	wire [7:0] reg_dat_do;

	reg         reg_dat_we;
	reg         reg_dat_re;

	wire        reg_dat_wait;
	wire        reg_dat_rdy;

	reg [3:0] recv_state;
	reg [15:0] recv_divcnt;
	reg [7:0] recv_pattern;
	reg [7:0] recv_buf_data;
	reg recv_buf_valid;

	reg [9:0] send_pattern;
	reg [3:0] send_bitcnt;
	reg [15:0] send_divcnt;
	reg send_dummy;

	assign reg_div_do = cfg_divider;

	assign reg_dat_wait = reg_dat_we && (send_bitcnt || send_dummy);
	assign reg_dat_do = recv_buf_valid ? recv_buf_data : ~0;
	assign reg_dat_rdy = recv_buf_valid;

//	assign DO = ~(CS && RW) ? 8'hXX :
//				(ADDR == 0) ? reg_dat_do :
//				{6'h00, reg_dat_wait, reg_dat_rdy};
//	assign reg_dat_re = (CS && RW) && (ADDR == 0) ? 1 : 0;

//	assign reg_dat_di = DI;
//	assign reg_dat_we = (CS && ~RW) && (ADDR == 0) ? 1 : 0;

	always @(posedge CLK) begin
		if (RESET) begin
			cfg_divider <= DEFAULT_DIV;
		end else begin
			reg_dat_re <= 0;
			reg_dat_we <= 0;
			if (CS) begin
				if (RW) begin
					if (ADDR == 0) begin
						DO <= reg_dat_do;
						reg_dat_re <= 1;
					end else begin
						DO <= {6'h00, reg_dat_wait, reg_dat_rdy};
					end
				end else begin
					if (ADDR == 0) begin
						reg_dat_di <= DI;
						reg_dat_we <= 1;
					end
				end
			end
		end
	end

	always @(posedge CLK) begin
		if (RESET) begin
			recv_state <= 0;
			recv_divcnt <= 0;
			recv_pattern <= 0;
			recv_buf_data <= 0;
			recv_buf_valid <= 0;
		end else begin
			recv_divcnt <= recv_divcnt + 1;
			if (reg_dat_re)
				recv_buf_valid <= 0;
			case (recv_state)
				0: begin
					if (!ser_rx)
						recv_state <= 1;
					recv_divcnt <= 0;
				end
				1: begin
					if (2*recv_divcnt > cfg_divider) begin
						recv_state <= 2;
						recv_divcnt <= 0;
					end
				end
				10: begin
					if (recv_divcnt > cfg_divider) begin
						recv_buf_data <= recv_pattern;
						recv_buf_valid <= 1;
						recv_state <= 0;
					end
				end
				default: begin
					if (recv_divcnt > cfg_divider) begin
						recv_pattern <= {ser_rx, recv_pattern[7:1]};
						recv_state <= recv_state + 1;
						recv_divcnt <= 0;
					end
				end
			endcase
		end
	end

	assign ser_tx = send_pattern[0];

	always @(posedge CLK) begin
//		if (~ADDR[2] && CS && ~RW)  // Send dummy byte during divider setup
//			send_dummy <= 1;
		send_divcnt <= send_divcnt + 1;
		if (RESET) begin
			send_pattern <= ~0;
			send_bitcnt <= 0;
			send_divcnt <= 0;
			send_dummy <= 1;
		end else begin
			if (send_dummy && !send_bitcnt) begin
				send_pattern <= ~0;
				send_bitcnt <= 15;
				send_divcnt <= 0;
				send_dummy <= 0;
			end else
			if (reg_dat_we && !send_bitcnt) begin
				send_pattern <= {1'b1, reg_dat_di, 1'b0};
				send_bitcnt <= 10;
				send_divcnt <= 0;
			end else
			if (send_divcnt > cfg_divider && send_bitcnt) begin
				send_pattern <= {1'b1, send_pattern[9:1]};
				send_bitcnt <= send_bitcnt - 1;
				send_divcnt <= 0;
			end
		end
	end
endmodule

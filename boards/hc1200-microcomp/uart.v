module uart(
	input wire clk,
	input wire reset,
	input wire a0,
	input wire [7:0] din,
	output wire [7:0] dout,
	input wire rnw,
	input wire cs,
	input wire rxd,
	output wire txd
	);

	// CLKSPEED is the main clock speed
	parameter CLKSPEED = 2080000;

	// BAUD is the desired serial baud rate
	parameter BAUD = 115200;

	// DIVISOR is the number of clk cycles per bit time
	parameter DIVISOR = CLKSPEED / BAUD;

	// Registers
	reg [15:0] rx_bit_cnt;
	reg [15:0] tx_bit_cnt;
	reg [10:0] tx_shift_reg;
	reg [9:0]  rx_shift_reg;
	reg        rxd1;
	reg        rxd2;

	wire rx_busy;
	wire rx_full;
	wire tx_busy;

	// Assignments
	assign rx_busy = rx_shift_reg != 10'b1111111111;   
	assign rx_full = !rx_shift_reg[0]; 
	assign tx_busy = tx_shift_reg != 11'b1;
	assign txd = tx_shift_reg[0];
	assign dout = a0 ? rx_shift_reg[9:2] : { 6'b0, tx_busy, rx_full };

	// UART Receiver
	always @ (negedge clk) begin
		rxd1 <= rxd;
		rxd2 <= rxd1;
		if (reset) begin
			rx_shift_reg <= 10'b1111111111;
		end else if (rx_full) begin
			if (cs && rnw && a0) begin
				rx_shift_reg <= 10'b1111111111;
			end
		end else if (rx_busy) begin
			if (rx_bit_cnt == 0) begin
				rx_bit_cnt <= DIVISOR;
				rx_shift_reg <= {rxd1 , rx_shift_reg[9:1]};
			end else begin
				rx_bit_cnt <= rx_bit_cnt - 1;   
			end
		end else if (!rxd1 && rxd2) begin
			rx_shift_reg <= 10'b0111111111;         
			rx_bit_cnt <= DIVISOR >> 1;
		end
	end

	// UART Transmitter
	always @ (posedge clk) begin
		if (reset) begin
			tx_shift_reg <= 11'b1;
		end else if (tx_busy) begin
			if (tx_bit_cnt == 0) begin
				tx_shift_reg <= {1'b0 , tx_shift_reg[10:1]};
				tx_bit_cnt <= DIVISOR - 1;
			end else begin
				tx_bit_cnt <= tx_bit_cnt - 1;
			end
		end else if (cs && !rnw && a0) begin
			tx_shift_reg <= {2'b11, din[7:0], 1'b0};
			tx_bit_cnt <= DIVISOR - 1;
		end
	end
endmodule

/*
	GPIO interface
	
	$00..$01 - GPIO 15 bit
	$02..$03 - GPIO Direction bits (1 - out, 0 - in)
 */
module gpio (
	input wire clk,
	input wire rst,
	input wire [1:0] AD,
	input wire [7:0] DI,
	output wire [7:0] DO,
	input wire rw,
	input wire cs,
	
	inout wire [14:0] gpio
);
	reg [14:0] gpio_dir;
	reg [14:0] gpio_out;

	assign gpio[ 0] = gpio_dir[ 0] ? gpio_out[ 0] : 1'bZ;
	assign gpio[ 1] = gpio_dir[ 1] ? gpio_out[ 1] : 1'bZ;
	assign gpio[ 2] = gpio_dir[ 2] ? gpio_out[ 2] : 1'bZ;
	assign gpio[ 3] = gpio_dir[ 3] ? gpio_out[ 3] : 1'bZ;
	assign gpio[ 4] = gpio_dir[ 4] ? gpio_out[ 4] : 1'bZ;
	assign gpio[ 5] = gpio_dir[ 5] ? gpio_out[ 5] : 1'bZ;
	assign gpio[ 6] = gpio_dir[ 6] ? gpio_out[ 6] : 1'bZ;
	assign gpio[ 7] = gpio_dir[ 7] ? gpio_out[ 7] : 1'bZ;
	
	assign gpio[ 8] = gpio_dir[ 8] ? gpio_out[ 8] : 1'bZ;
	assign gpio[ 9] = gpio_dir[ 9] ? gpio_out[ 9] : 1'bZ;
	assign gpio[10] = gpio_dir[10] ? gpio_out[10] : 1'bZ;
	assign gpio[11] = gpio_dir[11] ? gpio_out[11] : 1'bZ;
	assign gpio[12] = gpio_dir[12] ? gpio_out[12] : 1'bZ;
	assign gpio[13] = gpio_dir[13] ? gpio_out[13] : 1'bZ;
	assign gpio[14] = gpio_dir[14] ? gpio_out[14] : 1'bZ;
//	assign gpio[15] = gpio_dir[15] ? gpio_out[15] : 1'bZ;

	wire [14:0] gpio_in;
		assign gpio_in[ 0] = gpio_dir[ 0] ? gpio_out[ 0] : gpio[ 0];
	assign gpio_in[ 1] = gpio_dir[ 1] ? gpio_out[ 1] : gpio[ 1];
	assign gpio_in[ 2] = gpio_dir[ 2] ? gpio_out[ 2] : gpio[ 2];
	assign gpio_in[ 3] = gpio_dir[ 3] ? gpio_out[ 3] : gpio[ 3];
	assign gpio_in[ 4] = gpio_dir[ 4] ? gpio_out[ 4] : gpio[ 4];
	assign gpio_in[ 5] = gpio_dir[ 5] ? gpio_out[ 5] : gpio[ 5];
	assign gpio_in[ 6] = gpio_dir[ 6] ? gpio_out[ 6] : gpio[ 6];
	assign gpio_in[ 7] = gpio_dir[ 7] ? gpio_out[ 7] : gpio[ 7];
	assign gpio_in[ 8] = gpio_dir[ 8] ? gpio_out[ 8] : gpio[ 8];
	assign gpio_in[ 9] = gpio_dir[ 9] ? gpio_out[ 9] : gpio[ 9];
	assign gpio_in[10] = gpio_dir[10] ? gpio_out[10] : gpio[10];
	assign gpio_in[11] = gpio_dir[11] ? gpio_out[11] : gpio[11];
	assign gpio_in[12] = gpio_dir[12] ? gpio_out[12] : gpio[12];
	assign gpio_in[13] = gpio_dir[13] ? gpio_out[13] : gpio[13];
	assign gpio_in[14] = gpio_dir[14] ? gpio_out[14] : gpio[14];
//	assign gpio_in[15] = gpio_dir[15] ? gpio_out[15] : gpio[15];


//	assign DO = (AD == 2'b00) ? {1'b0, gpio_in[14:8]} :
//				(AD == 2'b01) ? gpio_in[ 7:0] :
//				(AD == 2'b10) ? {1'b0, gpio_dir[14:8]} :
//				                gpio_dir[ 7:0];


	assign DO = (AD == 2'b00) ? {1'b1, gpio_in[14:8]} :
				(AD == 2'b01) ? gpio_in[ 7:0] :
				(AD == 2'b10) ? {1'b1, gpio_dir[14:8]} :
				                gpio_dir[ 7:0];
	always @ (posedge clk) begin
		if (rst) begin
			gpio_dir <= 0;
			gpio_out <= 0;
		end else if (cs && ~rw) begin
				case (AD[1:0])
				2'b00: gpio_out[14:8]  <= DI[6:0];
				2'b01: gpio_out[ 7:0]  <= DI;
				2'b10: gpio_dir[14:8]  <= DI[6:0];
				2'b11: gpio_dir[ 7:0]  <= DI;
				endcase
		end
	end
endmodule

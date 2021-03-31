/*
	GPIO interface
	
	$00 - KR3 | KR2 | KR1       | KR0   | MCS   | MSCK  | MISO  | MOSI
	$01 - 0   | 0   | REG_LATCH | BLANK | RS    | CLK   | CE    | DIN
	$04 - 1   | 1   | 1         | 1     | GPIO3 | GPIO2 | GPIO1 | GPIO 0
	$06 - 1   | 1   | 1         | 1     | DIR3  | DIR2  | DIR1  | DIR0
 */
module gpio (
	input wire clk,
	input wire rst,
	input wire [2:0] AD,
	input wire [7:0] DI,
	output wire [7:0] DO,
	input wire rw,
	input wire cs,
	
	inout wire [3:0] gpio,
	
	output wire gpio_mosi,
	input wire gpio_miso,
	output wire gpio_msck,
	output wire gpio_mcs,
	output wire gpio_din,
	output wire gpio_ce,
	output wire gpio_clk,
	output wire gpio_rs,
	output wire gpio_blank,
	output wire gpio_reg_latch,
	
	input wire [3:0] gpio_key_row
);
	reg [5:0] gpio0_out;

	assign gpio_din = gpio0_out[ 0];
	assign gpio_ce = gpio0_out[ 1];
	assign gpio_clk = gpio0_out[ 2];
	assign gpio_rs = gpio0_out[ 3];
	assign gpio_blank = gpio0_out[ 4];
	assign gpio_reg_latch = gpio0_out[ 5];

	reg [2:0] gpio1_out;

	assign gpio_mosi = gpio1_out[0];
	assign gpio_msck = gpio1_out[1];
	assign gpio_mcs = gpio1_out[2];

	reg [3:0] gpio_dir;
	reg [3:0] gpio_out;
	wire [3:0] gpio_in;

	assign gpio[ 0] = gpio_dir[ 0] ? gpio_out[ 0] : 1'bZ;
	assign gpio[ 1] = gpio_dir[ 1] ? gpio_out[ 1] : 1'bZ;
	assign gpio[ 2] = gpio_dir[ 2] ? gpio_out[ 2] : 1'bZ;
	assign gpio[ 3] = gpio_dir[ 3] ? gpio_out[ 3] : 1'bZ;
	assign gpio_in[0] = gpio_dir[0] ? gpio_out[0] : gpio[0];
	assign gpio_in[1] = gpio_dir[1] ? gpio_out[1] : gpio[1];
	assign gpio_in[2] = gpio_dir[2] ? gpio_out[2] : gpio[2];
	assign gpio_in[3] = gpio_dir[3] ? gpio_out[3] : gpio[3];
	
	assign DO = (AD == 3'b000) ? {gpio_key_row, gpio1_out[2], gpio1_out[1], gpio_miso, gpio1_out[0]} :
				(AD == 3'b001) ? {2'b00, gpio0_out} :
				(AD == 3'b100) ? {4'b1111, gpio_in} :
				(AD == 3'b110) ? {4'b1111, gpio_dir} :
				 8'hff;
	always @ (posedge clk) begin
		if (rst) begin
			gpio_dir <= 0;
			gpio_out <= 0;
		end else if (cs && ~rw) begin
				case (AD[2:0])
				3'b000: gpio1_out <= {DI[3], DI[2], DI[0]};
				3'b001: gpio0_out <= DI[5:0];
				3'b100: gpio_out[3:0]  <= DI[3:0];
				3'b110: gpio_dir[3:0]  <= DI[3:0];
				endcase
		end
	end
endmodule

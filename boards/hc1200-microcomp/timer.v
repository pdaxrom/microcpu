/*
	Timer interface
	
	$01..$00 - DIVISOR
	$02      - Status: bit 1 - stopped, bit 0 - interrupt
 */
module timer (
	input wire clk,
	input wire rst,
	input wire [1:0] AD,
	input wire [7:0] DI,
	output wire [7:0] DO,
	input wire rw,
	input wire cs,
	
	output wire intr
);
	reg [16:0]	counter;
	reg			intr_i;

	assign intr = intr_i;

	assign DO = (AD == 2'b00) ? counter[ 7:0] :
	            (AD == 2'b01) ? counter[15:8] :
	            {5'b0, counter[16], intr_i};
	
	always @ (posedge clk) begin
		if (rst) counter[16] <= 1;
		else if (~counter[16]) counter <= counter - 1;

		if (cs && ~rw && ~AD[1]) begin
			if (AD[0] == 2'b00) counter[ 7:0] <= DI;
			else counter[16:8] <= {1'b0, DI};
		end
	end
	
	always @ (negedge clk) begin
		if (rst) intr_i <= 0;
		else if (counter == 1) intr_i <= 1;
		else if (cs && AD[1]) intr_i <= 0;
	end
endmodule

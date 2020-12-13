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
	
	output reg intr
);
	reg [16:0]	counter;

	assign DO = (AD == 2'b00) ? counter[ 7:0] :
	            (AD == 2'b01) ? counter[15:8] :
	            (AD == 2'b10) ? {5'b0, counter[16], intr} :
	             8'hFF;
	
	always @ (posedge clk) begin
		if (rst) begin
			counter <= 17'b1;
			intr <= 0;
		end else if (~counter[16]) begin
			counter <= counter - 1;
//			if (counter == 0) intr <= 1;
			intr <= counter == 0;
		end else if (cs && AD[1]) intr <= 0;

		if (cs) begin
			if (~rw && ~AD[1]) begin
				if (AD[0] == 2'b00) counter[ 7:0] <= DI;
				else counter[16:8] <= {1'b0, DI};
			end
		end
	end
endmodule

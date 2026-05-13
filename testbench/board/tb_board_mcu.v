`timescale 1ns/1ps

module tb_board_mcu;
	localparam integer BIT_TIME = 2310;

	reg res;
	reg rx;
	wire tx;
	wire [14:0] gpio;

	assign gpio = 15'hzzzz;

	demo dut (
		.res(res),
		.rx(rx),
		.tx(tx),
		.gpio(gpio)
	);

	initial begin
		res = 0;
		rx = 1;
		#100;
		res = 1;
		fork
			begin
				expect_uart(8'h4d);
				$display("PASS: hc1200-mcu UART smoke");
				$finish_and_return(0);
			end
			begin
				#2000000;
				$display("FAIL: hc1200-mcu UART smoke timeout");
				$finish_and_return(1);
			end
		join
	end

	task expect_uart;
		input [7:0] expected;
		reg [7:0] got;
		integer bit_index;
		begin
			got = 0;
			wait (tx === 1'b0);
			#(BIT_TIME + (BIT_TIME / 2));
			for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
				got[bit_index] = tx;
				#BIT_TIME;
			end
			if (got != expected) begin
				$display("FAIL: hc1200-mcu UART got %02x expected %02x", got, expected);
				$finish_and_return(1);
			end
		end
	endtask
endmodule

`timescale 1ns/1ps

module tb_board_microcomp;
	localparam integer BIT_TIME = 2310;

	reg res;
	reg rx;
	wire tx;
	wire [3:0] gpio;
	wire gpio_mosi;
	reg gpio_miso;
	wire gpio_msck;
	wire gpio_mcs;
	wire gpio_din;
	wire gpio_ce;
	wire gpio_clk;
	wire gpio_rs;
	wire gpio_blank;
	wire gpio_reg_latch;
	reg [3:0] gpio_key_row;

	assign gpio = 4'hz;

	demo dut (
		.res(res),
		.rx(rx),
		.tx(tx),
		.gpio(gpio),
		.gpio_mosi(gpio_mosi),
		.gpio_miso(gpio_miso),
		.gpio_msck(gpio_msck),
		.gpio_mcs(gpio_mcs),
		.gpio_din(gpio_din),
		.gpio_ce(gpio_ce),
		.gpio_clk(gpio_clk),
		.gpio_rs(gpio_rs),
		.gpio_blank(gpio_blank),
		.gpio_reg_latch(gpio_reg_latch),
		.gpio_key_row(gpio_key_row)
	);

	initial begin
		res = 0;
		rx = 1;
		gpio_miso = 0;
		gpio_key_row = 0;
		#100;
		res = 1;
		fork
			begin
				expect_uart(8'h50);
				$display("PASS: hc1200-microcomp memmap smoke");
				$finish_and_return(0);
			end
			begin
				#3000000;
				$display("FAIL: hc1200-microcomp memmap smoke timeout");
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
				$display("FAIL: hc1200-microcomp UART got %02x expected %02x", got, expected);
				$finish_and_return(1);
			end
		end
	endtask
endmodule

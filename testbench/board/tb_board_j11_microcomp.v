`timescale 1ns/1ps

module tb_board_j11_microcomp;
	reg res;
	reg rx;
	wire tx;
	wire [3:0] gpio;
	wire gpio_mosi;
	wire gpio_miso;
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

	j11_hc1200_microcomp #(
		.UCODE_FILE("build/j11_microengine_smoke.words"),
		.FRAM_CLK_DIV(1)
	) dut (
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

	spi_fram_model fram (
		.cs_n(gpio_mcs),
		.sck(gpio_msck),
		.mosi(gpio_mosi),
		.miso(gpio_miso)
	);

	initial begin
		res = 0;
		rx = 1;
		gpio_key_row = 0;
		repeat (4) @(negedge dut.clk);
		res = 1;

		while (dut.debug_guest_r0 != 16'h1234) @(negedge dut.clk);
		if (fram.memory[17'h02000] !== 8'h34 ||
				fram.memory[17'h02001] !== 8'h12 ||
				dut.debug_cause !== 0 || tx !== 1'b1 ||
				gpio_blank !== 1'b1 || gpio_ce !== 1'b1) begin
			$display("FAIL: hc1200 J-11 board r0=%04x cause=%04x mem=%02x%02x",
				dut.debug_guest_r0, dut.debug_cause,
				fram.memory[17'h02001], fram.memory[17'h02000]);
			$finish_and_return(1);
		end

		$display("PASS: hc1200-microcomp J-11 hardware FRAM path");
		$finish_and_return(0);
	end

	initial begin
		#400000;
		$display("FAIL: hc1200 J-11 board timeout upc=%04x r0=%04x",
			dut.debug_upc, dut.debug_guest_r0);
		$finish_and_return(1);
	end

endmodule

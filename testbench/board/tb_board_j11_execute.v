`timescale 1ns/1ps

module tb_board_j11_execute;
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
		.UCODE_FILE("build/j11_ucode.words"),
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
		#1;
		$readmemh("build/guest_dl11_tx.hex", fram.memory);
		repeat (4) @(negedge dut.clk);
		res = 1;

		while (tx !== 1'b0) @(negedge dut.clk);
		while (dut.debug_cause != 16'h0003) @(negedge dut.clk);
		if (dut.debug_guest_r0 !== 16'h0041 ||
				dut.debug_guest_pc !== 16'h000c) begin
			$display("FAIL: board J-11 DL11 r0=%04x pc=%04x cause=%04x",
				dut.debug_guest_r0, dut.debug_guest_pc, dut.debug_cause);
			$finish_and_return(1);
		end

		$display("PASS: microasm11 guest drives HC1200 DL11 UART");
		$finish_and_return(0);
	end

	initial begin
		#1000000;
		$display("FAIL: board J-11 DL11 timeout pc=%04x cause=%04x tx=%0d",
			dut.debug_guest_pc, dut.debug_cause, tx);
		$finish_and_return(1);
	end

endmodule

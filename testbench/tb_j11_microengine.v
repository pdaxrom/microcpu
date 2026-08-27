`timescale 1ns/1ps

module tb_j11_microengine;
	reg clk;
	reg rst;
	wire guest_req;
	wire guest_write;
	wire guest_byte;
	wire guest_bank;
	wire [15:0] guest_address;
	wire [15:0] guest_wdata;
	wire [15:0] guest_rdata;
	wire guest_ready;
	wire guest_error;
	wire guest_busy;
	wire spi_cs_n;
	wire spi_sck;
	wire spi_mosi;
	wire spi_miso;
	wire [15:0] debug_upc;
	wire [15:0] debug_guest_r0;
	wire [15:0] debug_guest_pc;
	wire [15:0] debug_guest_psw;
	wire [15:0] debug_guest_ir;
	wire [15:0] debug_cause;
	wire [15:0] debug_pending_irq;
	wire guest_reset;
	integer guest_reset_count;

	j11_microengine #(
		.UROM_WORDS(1024),
		.UCODE_FILE("build/j11_microengine_smoke.words")
	) dut (
		.clk(clk),
		.rst(rst),
		.guest_req(guest_req),
		.guest_write(guest_write),
		.guest_byte(guest_byte),
		.guest_bank(guest_bank),
		.guest_address(guest_address),
		.guest_wdata(guest_wdata),
		.guest_rdata(guest_rdata),
		.guest_ready(guest_ready),
		.guest_error(guest_error),
		.irq(1'b0),
		.irq_level(3'b0),
		.irq_vector(8'b0),
		.guest_reset(guest_reset),
		.debug_upc(debug_upc),
		.debug_guest_r0(debug_guest_r0),
		.debug_guest_pc(debug_guest_pc),
		.debug_guest_psw(debug_guest_psw),
		.debug_guest_ir(debug_guest_ir),
		.debug_cause(debug_cause),
		.debug_pending_irq(debug_pending_irq)
	);

	spi_fram_guest_ram #(
		.CLK_DIV(1)
	) guest_ram (
		.clk(clk),
		.rst(rst),
		.req(guest_req),
		.write(guest_write),
		.byte_access(guest_byte),
		.bank(guest_bank),
		.address(guest_address),
		.wdata(guest_wdata),
		.rdata(guest_rdata),
		.ready(guest_ready),
		.error(guest_error),
		.busy(guest_busy),
		.spi_cs_n(spi_cs_n),
		.spi_sck(spi_sck),
		.spi_mosi(spi_mosi),
		.spi_miso(spi_miso)
	);

	spi_fram_model fram (
		.cs_n(spi_cs_n),
		.sck(spi_sck),
		.mosi(spi_mosi),
		.miso(spi_miso)
	);

	always #5 clk = !clk;
	always @(posedge clk) begin
		if (guest_reset) guest_reset_count = guest_reset_count + 1;
	end

	initial begin
		clk = 0;
		rst = 1;
		guest_reset_count = 0;
		repeat (4) @(negedge clk);
		rst = 0;

		while (debug_guest_r0 == 0 && debug_cause == 0) @(negedge clk);
		if (debug_guest_r0 !== 16'h1234 || debug_guest_pc !== 16'h1234 ||
				debug_guest_psw !== 0 || debug_guest_ir !== 0 ||
				debug_cause !== 0 || debug_pending_irq !== 0 || guest_reset_count !== 0 ||
				fram.memory[17'h02000] !== 8'h34 ||
				fram.memory[17'h02001] !== 8'h12) begin
			$display("FAIL: upc=%04x gpc=%04x gr0=%04x cause=%04x mem=%02x%02x",
				debug_upc, debug_guest_pc, debug_guest_r0, debug_cause,
				fram.memory[17'h02001], fram.memory[17'h02000]);
			$finish_and_return(1);
		end

		$display("PASS: J-11 microengine 32-word context and FRAM guest bus");
		$finish_and_return(0);
	end

	initial begin
		#300000;
		$display("FAIL: timeout upc=%04x gr0=%04x cause=%04x",
			debug_upc, debug_guest_r0, debug_cause);
		$finish_and_return(1);
	end

endmodule

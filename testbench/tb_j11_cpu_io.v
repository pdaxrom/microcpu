`timescale 1ns/1ps

module tb_j11_cpu_io;
	reg clk = 0, rst = 1;
	wire req, wr, byte_access, bank, ready, error, guest_reset, irq;
	wire [2:0] level;
	wire [7:0] vector;
	wire [15:0] address, wdata, rdata;
	wire tx, cs, sck, mosi, miso;
	reg [1023:0] program_file;
	integer cycles, expected_cause = 3, expected_cpuerr = -1;
	integer fault_read_address = -1, fault_write_address = -1;
	wire injected_error = ready && ((!wr && address == fault_read_address) ||
		(wr && address == fault_write_address));

	// All architectural assertions are assembled guest code, not testbench
	// mutations of processor state. Use the real board UART/time/FRAM path.
	j11_microengine #(.UROM_WORDS(`J11_UROM_WORDS),
		.UCODE_FILE("build/j11_ucode.words")) engine (
		.clk(clk), .rst(rst), .guest_req(req), .guest_write(wr),
		.guest_byte(byte_access), .guest_bank(bank), .guest_address(address),
		.guest_wdata(wdata), .guest_rdata(rdata), .guest_ready(ready),
		.guest_error(error || injected_error), .guest_reset(guest_reset), .irq(irq),
		.irq_level(level), .irq_vector(vector)
	);
	j11_hc1200_guest_bus #(.FRAM_CLK_DIV(1),
		.TICK_DIVISOR(1000000000)) services (
		.clk(clk), .rst(rst), .guest_reset(guest_reset), .req(req), .write(wr),
		.byte_access(byte_access), .bank(bank), .address(address), .wdata(wdata),
		.rdata(rdata), .ready(ready), .error(error), .busy(),
		.uart_rx(1'b1), .uart_tx(tx), .irq(irq), .irq_level(level), .irq_vector(vector),
		.spi_cs_n(cs), .spi_sck(sck), .spi_mosi(mosi), .spi_miso(miso)
	);
	spi_fram_model fram (.cs_n(cs), .sck(sck), .mosi(mosi), .miso(miso));
	always #5 clk = !clk;
	always @(posedge clk) if (!rst && req && ready) begin
		case (address & 16'hfffe)
			16'o177744, 16'o177746, 16'o177750, 16'o177752,
			16'o177766, 16'o177772, 16'o177776:
				$fatal(1, "Processor register leaked onto native bus: %06o", address);
		endcase
	end

	initial begin
		if (!$value$plusargs("PROGRAM=%s", program_file))
			$fatal(1, "Missing assembled guest PROGRAM");
		if ($value$plusargs("FAULT_READ=%o", fault_read_address)) begin end
		if ($value$plusargs("FAULT_WRITE=%o", fault_write_address)) begin end
		if ($value$plusargs("EXPECT_CAUSE=%d", expected_cause)) begin end
		if ($value$plusargs("EXPECT_CPUERR=%o", expected_cpuerr)) begin end
		#1;
		$readmemh(program_file, fram.memory);
		repeat (4) @(negedge clk);
		rst = 0;
		for (cycles = 0; cycles < 2000000 && engine.cause_reg < 3; cycles = cycles + 1)
			@(negedge clk);
		if (engine.cause_reg != expected_cause || engine.jctx[0] !== 16'o012345 ||
				(expected_cpuerr >= 0 && (engine.jctx[23] >> 8) !== expected_cpuerr)) begin
			$display("R3=%06o R4=%06o frame PC=%06o PSW=%06o",
				engine.jctx[3], engine.jctx[4],
				{fram.memory[engine.jctx[6]+1], fram.memory[engine.jctx[6]]},
				{fram.memory[engine.jctx[6]+3], fram.memory[engine.jctx[6]+2]});
			$fatal(1, "CPU I/O: %0s stage=%0d PC=%06o IR=%06o uPC=%04h PSW=%06o CPUERR=%03o R0=%06o R1=%06o R2=%06o SP=%06o",
				program_file, engine.jctx[5], engine.jctx[7], engine.jctx[9],
				engine.upc, engine.jctx[8], engine.jctx[23] >> 8,
				engine.jctx[0], engine.jctx[1], engine.jctx[2], engine.jctx[6]);
		end
		$display("PASS: %0s", program_file);
		$finish;
	end
endmodule

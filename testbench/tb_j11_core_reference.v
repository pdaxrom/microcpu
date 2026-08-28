`timescale 1ns/1ps

/* Instruction-level core checks use a deterministic flat RAM bus.
 * The separate j11-test suite exercises the real SPI FRAM/board path.
 */
module tb_j11_core_reference;
	reg clk = 0;
	reg rst = 1;
	wire req, wr, byte_access, bank;
	wire [15:0] address, wdata;
	reg [15:0] rdata = 0;
	reg ready = 0;
	reg error = 0;
	reg [7:0] memory [0:65535];
	reg [7:0] expected [0:65535];
	reg [15:0] fixture [0:44];
	integer fetch_pc, wait_pc, check_banks;
	integer i, cycles, started, done, failures, active_mode;

	j11_microengine #(.UROM_WORDS(`J11_UROM_WORDS),
		.UCODE_FILE("build/j11_ucode.words")) dut (
		.clk(clk), .rst(rst), .guest_req(req), .guest_write(wr),
		.guest_byte(byte_access), .guest_bank(bank), .guest_address(address),
		.guest_wdata(wdata), .guest_rdata(rdata), .guest_ready(ready),
		.guest_error(error), .irq(1'b0), .irq_level(3'b0), .irq_vector(8'b0)
	);
	`define J11_CONTEXT_ENGINE dut
	`include "include/j11_context_probe.vh"
	always #5 clk = !clk;
	always @(posedge clk) begin
		ready <= 0;
		if (!rst && req && !ready) begin
			ready <= 1;
			error <= !byte_access && address[0];
			if (byte_access || !address[0]) begin
				if (wr) begin
					memory[address] <= wdata[7:0];
					if (!byte_access) memory[address + 16'd1] <= wdata[15:8];
				end else begin
					rdata <= byte_access ? {8'b0, memory[address]} :
						{memory[address + 16'd1], memory[address]};
				end
			end
		end
	end

	initial begin
		if (!$value$plusargs("FETCH_PC=%h", fetch_pc) ||
				!$value$plusargs("WAIT_PC=%h", wait_pc) ||
				!$value$plusargs("CHECK_BANKS=%d", check_banks))
			$fatal(1, "Missing microcode boundary/coverage arguments");
		$readmemh("build/core_reference/input.hex", memory);
		$readmemh("build/core_reference/expected.hex", expected);
		$readmemh("build/core_reference/state.hex", fixture);
		repeat (4) @(negedge clk);
		rst = 0;
		while (dut.state != dut.ST_FETCH) @(negedge clk);
		// Deposit fixture state only after the engine's context clear sequence.
		for (i = 0; i < 9; i = i + 1) deposit_context(i, fixture[i]);
		dut.guest_r0_mirror = fixture[0];
		dut.guest_pc_mirror = fixture[7];
		dut.guest_psw_mirror = fixture[8];
		deposit_context(16, fixture[18]);
		deposit_context(17, fixture[19]);
		deposit_context(19, fixture[20]);
		// C lazily clones R0..R5 on the first RS change. Reproduce that fixture
		// state, not its reset policy: hardware reset zeros both independent sets.
		for (i = 0; i < 6; i = i + 1) deposit_context(32+i, fixture[32+i]);
		if (fixture[24]) begin
			dut.upc = wait_pc;
			deposit_cpu_io();
		end
		started = fixture[24] != 0;
		done = 0;
		for (cycles = 0; cycles < 200000 && !done; cycles = cycles + 1) begin
			@(negedge clk);
			if (dut.state == dut.ST_FETCH && dut.upc == fetch_pc) begin
				if (started) done = 1;
				else deposit_cpu_io(); // after reset init, before this instruction
				started = 1;
			end
			if (started && fixture[25] && dut.state == dut.ST_FETCH &&
					dut.upc == wait_pc) done = 1;
		end
		if (!done) $fatal(1, "Timeout: uPC=%04h PC=%06o cause=%04h",
			dut.upc, context_words[7], dut.cause_reg);
		failures = 0;
		if (fixture[44]) begin
			for (i = 0; i < 6; i = i + 1) begin
				if (context_words[32+i] !== fixture[38+i]) begin
					$display("inactive R%0d: got %06o expected %06o", i,
						context_words[32+i], fixture[38+i]);
					failures = failures + 1;
				end
			end
		end
		if ((context_words[23] >> 8) !== fixture[29] ||
				(context_words[21] & 16'hfe00) !== fixture[30] || context_words[31] !== fixture[31]) begin
			$display("CPU I/O: CPUERR=%06o/%06o PIRQ=%06o/%06o CCR=%06o/%06o (got/expected)",
				context_words[23] >> 8, fixture[29], context_words[21] & 16'hfe00,
				fixture[30], context_words[31], fixture[31]);
			failures = failures + 1;
		end
		for (i = 0; i < 9; i = i + 1) begin
			if (context_words[i] !== fixture[9 + i]) begin
				$display("state[%0d]: got %06o expected %06o", i, context_words[i], fixture[9 + i]);
				failures = failures + 1;
			end
		end
		if (check_banks) begin
			// The active SP is authoritative; inactive banks must also match.
			active_mode = (context_words[8] >> 14) & 3;
			if (active_mode == 2) active_mode = 0;
			for (i = 0; i < 4; i = i + 1) begin
				if (i != 2 && i != active_mode &&
						context_words[16 + i] !== fixture[21 + (i == 3 ? 2 : i)]) begin
					$display("SP bank %0d: got %06o expected %06o", i,
						context_words[16 + i], fixture[21 + (i == 3 ? 2 : i)]);
					failures = failures + 1;
				end
			end
		end
		for (i = 0; i < 65536; i = i + 1) begin
			if (memory[i] !== expected[i]) begin
				if (failures < 12) $display("memory[%06o]: got %03o expected %03o", i, memory[i], expected[i]);
				failures = failures + 1;
			end
		end
		if (failures) $finish_and_return(1);
		$finish;
	end

	task deposit_cpu_io;
		begin
			deposit_context(23, {fixture[26][7:0], context_words[23][7:0]});
			deposit_context(21, (context_words[21] & 16'h00ff) | (fixture[27] & 16'hfe00));
			deposit_context(31, fixture[28]);
		end
	endtask
endmodule

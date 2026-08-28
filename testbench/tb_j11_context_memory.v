`timescale 1ns/1ps

// Same assembled program against behavioral RAM and the physical EBR model.
// No deposited context: all data is written/read by native instructions.
module tb_j11_context_memory;
	reg clk = 0, rst = 1;
	wire req;
	integer i, run, cycles = 0, previous_fetch = -1, instructions = 0;
	reg reached_boundary = 0;
	j11_microengine #(.UROM_WORDS(`J11_UROM_WORDS),
		.UCODE_FILE("build/j11_context_memory.words")) dut (
		.clk(clk), .rst(rst), .guest_req(req),
		.guest_ready(1'b0), .guest_error(1'b0), .guest_rdata(16'b0),
		.irq(1'b0), .irq_level(3'b0), .irq_vector(8'b0)
	);
	`define J11_CONTEXT_ENGINE dut
	`include "include/j11_context_probe.vh"
	always #5 clk = !clk;
	always @(negedge clk) begin
		cycles = cycles + 1;
		if (cycles > 1000000)
			$fatal(1, "Shared context timeout: uPC=%h uIR=%h cause=%h state=%0d v0=%h v1=%h v2=%h v3=%h v4=%h",
				dut.upc, dut.uir, dut.cause_reg, dut.state,
				dut.r[3], dut.r[4], dut.r[5], dut.r[6], dut.r[7]);
		if (rst || dut.state == dut.ST_CLEAR) previous_fetch = -1;
		else if (dut.state == dut.ST_FETCH) begin
			if (previous_fetch >= 0 && cycles - previous_fetch != 6)
				$fatal(1, "Native instruction took %0d cycles instead of 6", cycles - previous_fetch);
			previous_fetch = cycles;
			instructions = instructions + 1;
			if (dut.upc == 2 * (dut.CONTEXT_BASE - 1)) reached_boundary = 1;
		end
		if (!rst && req) $fatal(1, "Context access escaped to guest RAM");
	end

	task reset_engine;
	begin
		rst = 1;
		repeat (4) @(negedge clk);
		#1; rst = 0;
		while (dut.state != dut.ST_FETCH) begin @(negedge clk); #1; end
		for (i = 0; i < 64; i = i + 1)
			if (context_words[i] !== 0) $fatal(1, "Reset did not clear context[%0d]", i);
	end
	endtask

	initial begin
		reset_engine();
		// Assert reset with a context store queued; clearing must restart at 0.
		while (!(dut.context_write_enable && dut.state == dut.ST_EXEC)) begin
			@(negedge clk); #1;
			if (dut.cause_reg != 0) $fatal(1, "Context program failed before its first store: %h", dut.upc);
		end
		reset_engine();
		for (run = 0; run < 2; run = run + 1) begin
			reached_boundary = 0;
			while (dut.cause_reg == 0) begin @(negedge clk); #1; end
			if (dut.cause_reg !== 2 || !reached_boundary)
				$fatal(1, "Shared context failed: cause=%h uPC=%h boundary=%b",
					dut.cause_reg, dut.upc, reached_boundary);
			if (run == 0) reset_engine();
		end
		$display("PASS: shared context patterns, index masking, PC accesses, last code word, reset and %0d six-cycle instructions", instructions);
		$finish;
	end
endmodule

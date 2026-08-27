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
	reg [15:0] fixture [0:31];
	integer fetch_pc, wait_pc, check_banks;
	integer i, cycles, started, done, failures, active_mode;

	j11_microengine #(.UROM_WORDS(`J11_UROM_WORDS),
		.UCODE_FILE("build/j11_ucode.words")) dut (
		.clk(clk), .rst(rst), .guest_req(req), .guest_write(wr),
		.guest_byte(byte_access), .guest_bank(bank), .guest_address(address),
		.guest_wdata(wdata), .guest_rdata(rdata), .guest_ready(ready),
		.guest_error(error), .irq(1'b0), .irq_level(3'b0), .irq_vector(8'b0)
	);
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
		// Deposit fixture state only after the engine's EBR clear sequence.
		for (i = 0; i < 9; i = i + 1) dut.jctx[i] = fixture[i];
		dut.guest_r0_mirror = fixture[0];
		dut.guest_pc_mirror = fixture[7];
		dut.guest_psw_mirror = fixture[8];
		dut.jctx[16] = fixture[18];
		dut.jctx[17] = fixture[19];
		dut.jctx[19] = fixture[20];
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
			dut.upc, dut.jctx[7], dut.cause_reg);
		failures = 0;
		if ((dut.jctx[23] >> 8) !== fixture[29] ||
				(dut.jctx[21] & 16'hfe00) !== fixture[30] || dut.jctx[31] !== fixture[31]) begin
			$display("CPU I/O: CPUERR=%06o/%06o PIRQ=%06o/%06o CCR=%06o/%06o (got/expected)",
				dut.jctx[23] >> 8, fixture[29], dut.jctx[21] & 16'hfe00,
				fixture[30], dut.jctx[31], fixture[31]);
			failures = failures + 1;
		end
		for (i = 0; i < 9; i = i + 1) begin
			if (dut.jctx[i] !== fixture[9 + i]) begin
				$display("state[%0d]: got %06o expected %06o", i, dut.jctx[i], fixture[9 + i]);
				failures = failures + 1;
			end
		end
		if (check_banks) begin
			// The active SP is authoritative; inactive banks must also match.
			active_mode = (dut.jctx[8] >> 14) & 3;
			if (active_mode == 2) active_mode = 0;
			for (i = 0; i < 4; i = i + 1) begin
				if (i != 2 && i != active_mode &&
						dut.jctx[16 + i] !== fixture[21 + (i == 3 ? 2 : i)]) begin
					$display("SP bank %0d: got %06o expected %06o", i,
						dut.jctx[16 + i], fixture[21 + (i == 3 ? 2 : i)]);
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
			dut.jctx[23] = {fixture[26][7:0], dut.jctx[23][7:0]};
			dut.jctx[21] = (dut.jctx[21] & 16'h00ff) | (fixture[27] & 16'hfe00);
			dut.jctx[31] = fixture[28];
		end
	endtask
endmodule

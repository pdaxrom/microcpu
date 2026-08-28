`include "include/j11_test_target.vh"
`timescale 1ns/1ps

// Architectural setup/checks are assembled guest code. The only injected
// state is the private console mailbox: the future ODT's HALT/Proceed source.
module tb_j11_halt;
	reg clk = 0, rst = 1, ready = 0, error = 0, irq = 0;
	wire req, wr, byte_access, bank, guest_reset;
	wire [15:0] address, wdata;
	reg [15:0] rdata = 0;
	reg [7:0] memory [0:65535];
	reg [15:0] saved_context [0:63];
	reg [15:0] frame_pc, frame_psw;
	integer i, cycles = 0, transactions = 0, resets = 0;
	integer saved_transactions, saved_resets;
	`J11_ENGINE_MODULE #(.UROM_WORDS(`J11_UROM_WORDS),
		.UCODE_FILE(`J11_UCODE_FILE)) dut (
		.clk(clk), .rst(rst), .guest_req(req), .guest_write(wr),
		.guest_byte(byte_access), .guest_bank(bank), .guest_address(address),
		.guest_wdata(wdata), .guest_rdata(rdata), .guest_ready(ready),
		.guest_error(error), .guest_reset(guest_reset), .irq(irq),
		.irq_level(3'd4), .irq_vector(8'o60)
	);
	`define J11_CONTEXT_ENGINE dut
	`include "include/j11_context_probe.vh"
	always #5 clk = !clk;
	always @(posedge clk) begin
		ready <= 0;
		if (guest_reset) resets = resets + 1;
		if (!rst && req && !ready) begin
			transactions = transactions + 1;
			ready <= 1;
			error <= !byte_access && address[0];
			if (byte_access || !address[0]) begin
				if (wr) begin
					memory[address] <= wdata[7:0];
					if (!byte_access) memory[address + 16'd1] <= wdata[15:8];
				end else rdata <= byte_access ? {8'b0, memory[address]} :
					{memory[address + 16'd1], memory[address]};
			end
		end
		cycles = cycles + 1;
		if (cycles > 2000000)
			$fatal(1, "HALT timeout: stage=%0d PC=%06o uPC=%04h cause=%0d",
				word_at(16'o6000), context_words[7], dut.upc, dut.cause_reg);
	end
	function [15:0] word_at(input [15:0] a);
		word_at = {memory[a + 16'd1], memory[a]};
	endfunction
	task stop_at(input integer stage, input [15:0] pc, input [15:0] psw,
		input [15:0] sp);
	begin
		while (dut.cause_reg < 3) @(negedge clk);
		if (dut.cause_reg != 3 || word_at(16'o6000) != stage ||
				context_words[7] !== pc || context_words[8] !== psw || context_words[6] !== sp)
			$fatal(1, "HALT stage %0d: stage=%0d PC=%06o PSW=%06o SP=%06o R0=%06o",
				stage, word_at(16'o6000), context_words[7], context_words[8], context_words[6], context_words[0]);
		for (i = 0; i < 64; i = i + 1) saved_context[i] = context_words[i];
		saved_transactions = transactions;
		saved_resets = resets;
		repeat (500) @(negedge clk);
		for (i = 0; i < 64; i = i + 1)
			if (context_words[i] !== saved_context[i])
				$fatal(1, "Context %0d changed during HALT", i);
		if (transactions != saved_transactions || resets != saved_resets || req)
			$fatal(1, "HALT accessed guest bus or reset peripherals");
	end
	endtask
	task proceed(input [15:0] command);
	begin
		deposit_context(38, command);
		while (dut.cause_reg == 3) @(negedge clk);
	end
	endtask
	initial begin
		for (i = 0; i < 65536; i = i + 1) memory[i] = 0;
		$readmemh("build/guest_halt_console.hex", memory);
		repeat (4) @(negedge clk);
		rst = 0;
		stop_at(1, word_at(16'o100), 16'o4013, 16'o10000);
		for (i = 0; i < 6; i = i + 1)
			if (context_words[i] !== 16'o200 + i || context_words[32+i] !== 16'o100 + i)
				$fatal(1, "HALT lost register set at R%0d", i);
		irq = 1;
		@(negedge clk);
		irq = 0;
		stop_at(1, word_at(16'o100), 16'o4013, 16'o10000);
		if (dut.pending_irq_reg !== 16'h8430) $fatal(1, "IRQ not latched in HALT");
		proceed(2);
		stop_at(2, word_at(16'o102), 16'o4003, 16'o10000);
		proceed(3);
		stop_at(2, word_at(16'o104), 16'o4001, 16'o10000);
		if (word_at(16'o6002) != 2) $fatal(1, "Proceed did not single-step");
		frame_pc = word_at(16'o7774);
		frame_psw = word_at(16'o7776);
		proceed(3);
		stop_at(2, word_at(16'o112), 16'o4001, 16'o10000);
		if (word_at(16'o7774) !== frame_pc || word_at(16'o7776) !== frame_psw)
			$fatal(1, "HALT at vector entry overwrote the guest stack");
		proceed(2);
		while (context_words[7] != word_at(16'o106) && dut.cause_reg < 3) @(negedge clk);
		// Allow WAIT to settle; then a HALT request stops user mode without 004.
		repeat (500) @(negedge clk);
		if (dut.cause_reg >= 3) $fatal(1, "Failed before WAIT");
		deposit_context(38, 1);
		stop_at(3, word_at(16'o106), 16'o144000, 16'o14000);
		proceed(2);
		stop_at(4, word_at(16'o110), 16'o4020, 16'o10000);
		if (word_at(16'o6006) != 0) $fatal(1, "HALT itself caused TRACE");
		proceed(2);
		while (dut.cause_reg < 3) @(negedge clk);
		if (dut.cause_reg != 3 || context_words[0] !== 16'o12345 || word_at(16'o6000) != 5)
			$fatal(1, "HALT guest checks failed at PC=%06o", context_words[7]);
		$display("PASS: console HALT, preserved RS/SP/PSW, pending IRQ, Proceed, single-step, vector priority, user WAIT and TRACE");
		$finish;
	end
endmodule

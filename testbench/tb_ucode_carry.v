`timescale 1ns/1ps

// Encoding/pipeline unit test. Executable carry chains also live in ucode_native.asm.
module tb_ucode_carry;
	reg clk = 0;
	ucode_cpu #(.UROM_WORDS(512)) dut (
		.clk(clk), .rst(1'b0), .guest_ready(1'b0), .guest_error(1'b0),
		.guest_rdata(16'b0), .irq(1'b0), .irq_level(3'b0), .irq_vector(8'b0)
	);
	integer i, j, op, c, alias_rd, checked = 0;
	reg [15:0] values [0:9];
	reg [31:0] rng = 32'hc0ffee42;

	task tick;
		begin #1; clk = 1; #1; clk = 0; #1; end
	endtask
	task check;
		input [15:0] a, b;
		input subtract, carry;
		input integer rd;
		input immediate;
		reg [15:0] instruction, result, saved [0:7];
		reg [3:0] flags;
		integer signed_a, signed_b, wide_signed, wide_unsigned, k;
		begin
			signed_a = a[15] ? a - 65536 : a;
			signed_b = b[15] ? b - 65536 : b;
			wide_signed = subtract ? signed_a - signed_b - carry : signed_a + signed_b + carry;
			wide_unsigned = subtract ? a - b - carry : a + b + carry;
			result = wide_unsigned;
			flags = {result[15], result == 0,
				(wide_signed < -32768 || wide_signed > 32767),
				(subtract ? wide_unsigned < 0 : wide_unsigned > 65535)};
			instruction = 0;
			instruction[7:3] = subtract ? 5'h0d : 5'h07;
			instruction[2:0] = rd;
			instruction[15:13] = 3;
			instruction[12:8] = immediate ? {b[3:0], 1'b1} : {3'd4, 2'b00};
			for (k = 0; k < 8; k = k + 1) begin
				saved[k] = 16'h1230 + k;
				if (k == 3) saved[k] = a;
				if (k == 4) saved[k] = b;
				dut.r[k] = saved[k];
			end
			dut.urom[0] = instruction;
			dut.word_pc = 0; dut.state = dut.ST_FETCH;
			dut.alu_flags = {3'b111, carry}; dut.guest_req = 0;
			repeat (6) tick();
			if (dut.r[rd] !== result || dut.alu_flags !== flags ||
					dut.state !== dut.ST_FETCH || dut.word_pc !== 12'd1 || dut.guest_req !== 0)
				$fatal(1, "ADC/SBC pipeline sub=%b a=%h b=%h C=%b rd=%0d imm=%b result=%h/%h flags=%h/%h",
					subtract, a, b, carry, rd, immediate, dut.r[rd], result, dut.alu_flags, flags);
			for (k = 0; k < 8; k = k + 1)
				if (k != rd && dut.r[k] !== saved[k]) $fatal(1, "ADC/SBC wrote register %0d", k);
			checked = checked + 1;
		end
	endtask
	initial begin
		values[0] = 0; values[1] = 1; values[2] = 2; values[3] = 15;
		values[4] = 16'h7ffe; values[5] = 16'h7fff; values[6] = 16'h8000;
		values[7] = 16'h8001; values[8] = 16'hfffe; values[9] = 16'hffff;
		#1;
		for (op = 0; op < 2; op = op + 1)
		for (c = 0; c < 2; c = c + 1)
		for (alias_rd = 3; alias_rd <= 5; alias_rd = alias_rd + 1)
		for (i = 0; i < 10; i = i + 1) begin
			for (j = 0; j < 10; j = j + 1)
				check(values[i], values[j], op, c, alias_rd, 0);
			for (j = 0; j < 16; j = j + 1)
				check(values[i], j, op, c, alias_rd, 1);
		end
		for (i = 0; i < 20000; i = i + 1) begin
			rng = rng ^ (rng << 13); rng = rng ^ (rng >> 17); rng = rng ^ (rng << 5);
			for (op = 0; op < 2; op = op + 1)
			for (c = 0; c < 2; c = c + 1)
				check(rng[15:0], rng[31:16], op, c, 3 + i % 3, 0);
		end
		$display("PASS: %0d ADC/SBC result/NZVC, aliases, immediates and six-clock pipeline checks", checked);
		$finish;
	end
endmodule

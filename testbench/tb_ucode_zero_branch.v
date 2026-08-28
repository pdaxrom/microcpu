`timescale 1ns/1ps
// Native encoding/pipeline unit test; guest programs remain microasm11 sources.
module tb_ucode_zero_branch;
	reg clk = 0;
	ucode_cpu #(.UROM_WORDS(4096)) dut (
		.clk(clk), .rst(1'b0), .guest_ready(1'b0), .guest_error(1'b0),
		.guest_rdata(16'b0), .irq(1'b0), .irq_level(3'b0), .irq_vector(8'b0)
	);
	integer p, r, d, nz, value, f, i, j, checked = 0, expected;
	reg [11:0] positions [0:3];
	reg [15:0] instruction, input_value, saved [0:7];
	reg take;
	task tick;
		begin #1; clk = 1; #1; clk = 0; #1; end
	endtask
	initial begin
		positions[0] = 0; positions[1] = 1;
		positions[2] = 2048; positions[3] = 4095;
		#1;
		for (p = 0; p < 4; p = p + 1)
		for (r = 0; r < 8; r = r + 1)
		for (d = -32; d < 32; d = d + 1)
		for (nz = 0; nz < 2; nz = nz + 1)
		for (value = 0; value < 2; value = value + 1)
		for (f = 0; f < 16; f = f + 1) begin
			instruction = 0;
			instruction[7:3] = 5'h1c;
			instruction[2:0] = r;
			instruction[15:14] = nz ? 2'b10 : 2'b01;
			instruction[13:8] = d;
			for (i = 0; i < 8; i = i + 1) begin
				saved[i] = 16'h1234 + i;
				if (i == r) saved[i] = value ? 16'h8001 : 16'h0000;
				dut.r[i] = saved[i];
			end
			input_value = r == 0 ? ((positions[p] << 1) | 1) : saved[r];
			take = (input_value == 0) ^ nz;
			expected = (positions[p] + (take ? d : 1)) & 4095;
			dut.urom[positions[p]] = instruction;
			dut.word_pc = positions[p]; dut.state = dut.ST_FETCH;
			dut.alu_flags = f; dut.guest_req = 0;
			repeat (6) tick();
			if (dut.state !== dut.ST_FETCH || dut.word_pc !== expected ||
					dut.alu_flags !== (f & 15) || dut.guest_req !== 0)
				$fatal(1, "CBZ pipeline p=%h rd=%d disp=%d nz=%d value=%h flags=%h target=%h expected=%h",
					positions[p], r, d, nz, input_value, f, dut.word_pc, expected);
			for (j = 0; j < 8; j = j + 1)
				if (dut.r[j] !== saved[j]) $fatal(1, "CBZ wrote register %d", j);
			checked = checked + 1;
		end
		$display("PASS: %d CBZ/CBNZ encodings, registers, flags, six-clock pipeline and PC wraps", checked);
		$finish;
	end
endmodule

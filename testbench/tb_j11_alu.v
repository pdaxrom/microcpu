`timescale 1ns/1ps

// Native RISC combinational ALU equivalence test, not a guest instruction
// fixture. Guest ISA programs remain assembly built with microasm11.
module tb_j11_alu;
	j11_microengine #(.UROM_WORDS(512)) dut (
		.clk(1'b0), .rst(1'b1), .guest_ready(1'b0), .guest_error(1'b0),
		.guest_rdata(16'b0), .irq(1'b0), .irq_level(3'b0), .irq_vector(8'b0)
	);
	reg [15:0] boundaries [0:8];
	reg [15:0] a, b;
	integer i, j, seed = 12345, checked = 0;
	task check;
		input [3:0] operation;
		input [15:0] left, right;
		reg [16:0] result;
		reg [8:0] byte_result;
		reg [3:0] flags;
		begin
			dut.operand_a = left;
			dut.operand_b = right;
			dut.urom_data = 0;
			dut.urom_data[7:4] = operation;
			if (operation == dut.ALU_SUBB) begin
				byte_result = {1'b0, left[7:0]} - {1'b0, right[7:0]};
				result = {9'b0, byte_result[7:0]};
				flags = {byte_result[7], byte_result[7:0] == 0,
					(left[7] ^ right[7]) & (left[7] ^ byte_result[7]), byte_result[8]};
			end else if (operation == dut.ALU_ADD) begin
				result = {1'b0, left} + {1'b0, right};
				flags = {result[15], result[15:0] == 0,
					~(left[15] ^ right[15]) & (left[15] ^ result[15]), result[16]};
			end else begin
				result = {1'b0, left} - {1'b0, right};
				flags = {result[15], result[15:0] == 0,
					(left[15] ^ right[15]) & (left[15] ^ result[15]), result[16]};
			end
			#1;
			if (dut.alu_result !== result || dut.alu_next_flags !== flags)
				$fatal(1, "ALU op=%h A=%h B=%h result=%h/%h NZVC=%h/%h",
					operation, left, right, dut.alu_result, result, dut.alu_next_flags, flags);
			checked = checked + 1;
		end
	endtask
	initial begin
		boundaries[0] = 0; boundaries[1] = 1; boundaries[2] = 16'h007f;
		boundaries[3] = 16'h0080; boundaries[4] = 16'h00ff; boundaries[5] = 16'h0100;
		boundaries[6] = 16'h7fff; boundaries[7] = 16'h8000; boundaries[8] = 16'hffff;
		for (i = 0; i < 9; i = i + 1)
			for (j = 0; j < 9; j = j + 1) begin
				check(dut.ALU_ADD, boundaries[i], boundaries[j]);
				check(dut.ALU_SUB, boundaries[i], boundaries[j]);
				check(dut.ALU_CMP, boundaries[i], boundaries[j]);
			end
		for (i = 0; i < 256; i = i + 1)
			for (j = 0; j < 256; j = j + 1)
				check(dut.ALU_SUBB, {j[7:0], i[7:0]}, {i[7:0], j[7:0]});
		for (i = 0; i < 8192; i = i + 1) begin
			a = $random(seed); b = $random(seed);
			check(dut.ALU_ADD, a, b);
			check(dut.ALU_SUB, a, b);
		end
		$display("PASS: %0d native ALU results/NZVC, including every byte subtraction", checked);
		$finish;
	end
endmodule

`timescale 1ns/1ps

// Combinational native-PC datapath test. Test instruction encodings are built
// from their fields here; guest executable fixtures remain microasm11 sources.
module tb_j11_pc;
	j11_microengine #(.UROM_WORDS(512)) dut (
		.clk(1'b0), .rst(1'b1), .guest_ready(1'b0), .guest_error(1'b0),
		.guest_rdata(16'b0), .irq(1'b0), .irq_level(3'b0), .irq_vector(8'b0)
	);
	reg [15:0] boundaries [0:10];
	reg [15:0] left, right;
	reg [16:0] result;
	reg n, z, v, c, taken;
	integer pc, offset, i, j, k, operation, condition, checked = 0;
	task check;
		input [15:0] want;
		reg [15:0] exposed_pc;
		begin
			exposed_pc = dut.upc + 1;
			#1;
			if (dut.next_pc !== want || dut.exec_pc !== exposed_pc)
				$fatal(1, "PC=%h IR=%h next=%h/%h operand-PC=%h/%h",
					dut.upc, dut.uir, dut.next_pc, want, dut.exec_pc, exposed_pc);
			checked = checked + 1;
		end
	endtask
	initial begin
		boundaries[0] = 0; boundaries[1] = 1; boundaries[2] = 16'h007f;
		boundaries[3] = 16'h0080; boundaries[4] = 16'h00ff; boundaries[5] = 16'h0100;
		boundaries[6] = 16'h7fff; boundaries[7] = 16'h8000;
		boundaries[8] = 16'hfffd; boundaries[9] = 16'hfffe; boundaries[10] = 16'hffff;
		dut.operand_a = 0; dut.operand_b = 0;
		// All 16-bit PCs, including odd values and wraparound, retain +1/+2.
		dut.uir = 0;
		dut.uir[7:4] = dut.INST_MOV;
		for (pc = 0; pc < 65536; pc = pc + 1) begin
			dut.upc = pc;
			check(pc + 2);
		end
		// Every signed branch displacement at each boundary PC.
		for (i = 0; i < 11; i = i + 1)
			for (offset = -1024; offset < 1024; offset = offset + 1) begin
				dut.upc = boundaries[i];
				dut.uir = 0;
				dut.uir[7:4] = dut.INST_B;
				dut.uir[15:8] = offset;
				dut.uir[2:0] = offset >>> 8;
				check(boundaries[i] + 2 * offset);
			end
		// Independent reference for all eight CMP/BIT skip conditions.
		for (operation = 0; operation < 2; operation = operation + 1)
			for (i = 0; i < 11; i = i + 1)
				for (j = 0; j < 11; j = j + 1)
					for (k = 0; k < 11; k = k + 1) begin
						left = boundaries[j]; right = boundaries[k];
						result = operation ? {1'b0, left & right} :
							{1'b0, left} - {1'b0, right};
						n = result[15]; z = result[15:0] == 0; c = result[16];
						v = (left[15] ^ right[15]) & (left[15] ^ result[15]);
						for (condition = 0; condition < 8; condition = condition + 1) begin
							case (condition)
							0: taken = z;
							1: taken = !z;
							2: taken = n;
							3: taken = v;
							4: taken = n ^ v;
							5: taken = !(n ^ v);
							6: taken = c;
							7: taken = !c;
							endcase
							dut.upc = boundaries[i];
							dut.operand_a = left; dut.operand_b = right;
							dut.uir = 0;
							dut.uir[7:4] = operation ? dut.ALU_BIT : dut.ALU_CMP;
							dut.uir[3] = 1;
							dut.uir[2:0] = condition;
							check(boundaries[i] + (taken ? 4 : 2));
						end
					end
		$display("PASS: %0d native PC fall-through/branch/skip/wraparound checks", checked);
		$finish;
	end
endmodule

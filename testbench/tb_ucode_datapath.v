`timescale 1ns/1ps

// Native encoding/datapath unit tests; executable fixtures are assembly.
module tb_ucode_datapath;
	reg clk = 0;
	ucode_cpu #(.UROM_WORDS(512)) dut (
		.clk(clk), .rst(1'b0), .guest_ready(1'b0), .guest_error(1'b0),
		.guest_rdata(16'b0), .irq(1'b0), .irq_level(3'b0), .irq_vector(8'b0)
	);
	integer p, d, i, op, checked = 0;
	reg [11:0] boundaries [0:5];

	task tick;
		begin #1; clk = 1; #1; clk = 0; #1; end
	endtask
	task check_pc;
		input integer expected;
		begin
			#1;
			if (dut.next_pc !== ((expected & 4095) << 1) ||
					dut.exec_pc !== ((dut.word_pc << 1) | 1))
				$fatal(1, "Word PC failed: PC=%h IR=%h next=%h expected word=%h",
					dut.upc, dut.uir, dut.next_pc, expected & 4095);
			checked = checked + 1;
		end
	endtask
	initial begin
		dut.state = dut.ST_FETCH;
		dut.skip_taken = 0;
		dut.operand_a = 0; dut.operand_b = 0;
		for (p = 0; p < 4096; p = p + 1) begin
			dut.word_pc = p; dut.uir = 16'h0080;
			check_pc(p + 1);
			dut.uir = 16'h0008;
			dut.skip_taken = 1; check_pc(p + 2);
			dut.skip_taken = 0; check_pc(p + 1);
		end
		boundaries[0] = 0; boundaries[1] = 1; boundaries[2] = 1023;
		boundaries[3] = 2048; boundaries[4] = 4094; boundaries[5] = 4095;
		for (i = 0; i < 6; i = i + 1)
			for (d = -1024; d < 1024; d = d + 1) begin
				dut.word_pc = boundaries[i]; dut.uir = 16'h00b0;
				dut.uir[15:8] = d; dut.uir[2:0] = d >>> 8;
				check_pc(boundaries[i] + d);
			end
		// Both absolute encodings, including their odd opcode halves; CALL LR
		// wraps at the code-window boundary and neither transfer changes flags.
		for (op = 0; op < 2; op = op + 1)
			for (p = 0; p < 4096; p = p + 1) begin
				dut.word_pc = 4095; dut.alu_flags = 4'ha;
				dut.uir = op ? 16'h00f0 : 16'h0070;
				dut.uir[3:0] = p >> 8; dut.uir[15:8] = p;
				dut.state = dut.ST_EXEC; tick();
				if (dut.word_pc !== p || dut.alu_flags !== 4'ha ||
						(!op && dut.r[2] !== 16'b0))
					$fatal(1, "Absolute transfer/LR failed at %h", p);
				checked = checked + 1;
			end
		// Every indirect byte address is aligned and confined to the window.
		for (p = 0; p < 65536; p = p + 1) begin
			dut.uir = 16'h6080; dut.operand_a = p;
			dut.state = dut.ST_EXEC; tick();
			if (dut.upc !== (p & 16'h1ffe)) $fatal(1, "MOV PC truncation");
			dut.uir = 16'h0090; dut.urom_data = p;
			dut.state = dut.ST_EXEC; tick();
			if (dut.upc !== (p & 16'h1ffe)) $fatal(1, "GGET PC truncation");
			checked = checked + 2;
		end
		$display("PASS: %0d ucode word-PC, transfer, alignment and wraparound checks", checked);
		$finish;
	end
endmodule

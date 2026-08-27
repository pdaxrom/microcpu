`timescale 1ns/1ps

// Native shifter state-transition test, not a guest program. Exercise every
// meaningful count, saturation, destination-PC writes and exact cycle count.
module tb_j11_shift;
	reg clk = 0, rst = 1;
	j11_microengine #(.UROM_WORDS(512)) dut (
		.clk(clk), .rst(rst), .guest_ready(1'b0), .guest_error(1'b0),
		.guest_rdata(16'b0), .irq(1'b0), .irq_level(3'b0), .irq_vector(8'b0)
	);
	reg [15:0] values [0:8], counts [0:24];
	integer i, j, direction, destination, cycles, checked = 0;
	always #5 clk = !clk;
	task check;
		input [15:0] value, amount;
		input left, pc_destination;
		reg [16:0] expected;
		reg [3:0] flags;
		integer count;
		begin
			count = amount > 17 ? 17 : amount;
			expected = left ? {1'b0, value} << count : {1'b0, value} >> count;
			flags = {expected[15], expected[15:0] == 0, 1'b0, expected[16]};
			@(negedge clk);
			dut.state = dut.ST_EXEC;
			dut.upc = 16'h0200;
			dut.urom_data = 0;
			dut.urom_data[7:4] = left ? dut.ALU_SHL : dut.ALU_SHR;
			dut.urom_data[3] = 1;
			dut.urom_data[2:0] = pc_destination ? 0 : 1;
			dut.operand_a = value;
			dut.operand_b = amount;
			dut.r[1] = 16'h5a5a;
			dut.alu_flags = 4'hf;
			cycles = 0;
			while (dut.state != dut.ST_FETCH) begin
				@(negedge clk);
				cycles = cycles + 1;
				if (cycles > 18) $fatal(1, "Shift did not finish");
			end
			if (cycles != count + 1 || dut.alu_flags !== flags ||
				dut.upc !== (pc_destination ? expected[15:0] : 16'h0202) ||
				dut.r[1] !== (pc_destination ? 16'h5a5a : expected[15:0]))
				$fatal(1, "Shift left=%0d PCdest=%0d value=%h count=%h result=%h/%h flags=%h/%h cycles=%0d/%0d",
					left, pc_destination, value, amount, dut.r[1], dut.upc,
					dut.alu_flags, flags, cycles, count + 1);
			checked = checked + 1;
		end
	endtask
	initial begin
		values[0] = 0; values[1] = 1; values[2] = 16'h007f;
		values[3] = 16'h0080; values[4] = 16'h00ff; values[5] = 16'h0100;
		values[6] = 16'h7fff; values[7] = 16'h8000; values[8] = 16'hffff;
		for (i = 0; i <= 20; i = i + 1) counts[i] = i;
		counts[21] = 31; counts[22] = 32; counts[23] = 256; counts[24] = 16'hffff;
		repeat (4) @(negedge clk);
		rst = 0;
		for (i = 0; i < 9; i = i + 1)
			for (j = 0; j < 25; j = j + 1)
				for (direction = 0; direction < 2; direction = direction + 1)
					for (destination = 0; destination < 2; destination = destination + 1)
						check(values[i], counts[j], direction != 0, destination != 0);
		$display("PASS: %0d native shifts, flags, PC destinations and exact cycle counts", checked);
		$finish;
	end
endmodule

`timescale 1ns/1ps

module tb_ucode_native;
	reg clk = 0, rst = 1;
	wire req, wr, byte_access, bank;
	wire [15:0] address, wdata;
	reg [15:0] rdata = 0;
	reg ready = 0, error = 0;
	reg [7:0] memory [0:65535];
	integer i, delay_count = 0, cycles = 0, last_fetch = -1, six_cycle_checks = 0;
	integer transactions = 0;
	reg memory_since_fetch = 0;
	reg [34:0] held_request;
	reg [15:0] code_before [0:`J11_UROM_WORDS-65];

	ucode_cpu #(.UROM_WORDS(`J11_UROM_WORDS),
		.UCODE_FILE("build/ucode_native.words")) dut (
		.clk(clk), .rst(rst), .guest_req(req), .guest_write(wr),
		.guest_byte(byte_access), .guest_bank(bank), .guest_address(address),
		.guest_wdata(wdata), .guest_rdata(rdata), .guest_ready(ready),
		.guest_error(error), .irq(1'b0), .irq_level(3'b0), .irq_vector(8'b0)
	);
	always #5 clk = !clk;
	always @(posedge clk) begin
		ready <= 0;
		if (rst || !req) delay_count <= 0;
		else if (!ready) begin
			if (delay_count == 0) held_request <= {wr, byte_access, bank, address, wdata};
			else if ({wr, byte_access, bank, address, wdata} !== held_request)
				$fatal(1, "Request changed during wait");
			if (delay_count == 3) begin
				ready <= 1;
				error <= !byte_access && address[0];
				delay_count <= 0;
				transactions <= transactions + 1;
				if (byte_access || !address[0]) begin
					if (wr) begin
						memory[address] <= wdata[7:0];
						if (!byte_access) memory[address+16'd1] <= wdata[15:8];
					end else rdata <= byte_access ? {8'b0, memory[address]} :
						{memory[address+16'd1], memory[address]};
				end
			end else delay_count <= delay_count + 1;
		end
	end

	always @(negedge clk) if (!rst) begin
		cycles = cycles + 1;
		if (dut.state == dut.ST_MEM) memory_since_fetch = 1;
		if (dut.state == dut.ST_FETCH) begin
			if (last_fetch >= 0 && !memory_since_fetch) begin
				if (cycles - last_fetch != 6) $fatal(1, "Native instruction latency changed");
				six_cycle_checks = six_cycle_checks + 1;
			end
			last_fetch = cycles;
			memory_since_fetch = 0;
		end
		if (cycles > 30000) $fatal(1, "Native test failed/hung at uPC=%h", dut.upc);
		if (dut.cause_reg == 2) begin
			if (transactions != 6 || six_cycle_checks < 1500)
				$fatal(1, "Missing native test coverage");
`ifndef J11_EBR_UROM
			for (i = 0; i < `J11_UROM_WORDS-64; i = i + 1)
				if (dut.urom[i] !== code_before[i]) $fatal(1, "Context overwrote code");
`endif
			$display("PASS: ucode LDI8 (256 values), 64-word context, jumps, flags, bus waits/errors; %0d six-cycle checks", six_cycle_checks);
			$finish;
		end
	end

	initial begin
		for (i = 0; i < 65536; i = i + 1) memory[i] = 0;
		#1;
`ifndef J11_EBR_UROM
		for (i = 0; i < `J11_UROM_WORDS-64; i = i + 1) code_before[i] = dut.urom[i];
`endif
		repeat (4) @(negedge clk);
		rst = 0;
	end
endmodule

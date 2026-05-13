`timescale 1ns/1ps

module test_bench;
	localparam TEST_INTR   = 16'hfffd;
	localparam TEST_STATUS = 16'hfffe;
	localparam TEST_PUTC   = 16'hffff;

	reg         clk;
	reg         rst;
	reg         intr;
	wire        read;
	wire [15:0] address;
	wire [7:0]  dout;
	wire [7:0]  din;

	reg [7:0] mem [0:65535];

	reg [1023:0] program_file;
	reg [1023:0] vcd_file;
	integer i;
	integer cycles;
	integer timeout_cycles;

	assign din = read ? mem[address] : 8'hff;

	cpu core1 (
		.clk(clk),
		.rst(rst),
		.read(read),
		.address(address),
		.dout(dout),
		.din(din),
		.intr(intr)
	);

	initial begin
		clk = 0;
		forever #5 clk = !clk;
	end

	initial begin
		rst = 1;
		intr = 0;
		cycles = 0;
		timeout_cycles = 20000;

		for (i = 0; i < 65536; i = i + 1) begin
			mem[i] = 8'h00;
		end

		if (!$value$plusargs("PROGRAM=%s", program_file)) begin
			$display("FAIL: missing +PROGRAM=<hex-file>");
			$finish_and_return(1);
		end

		if ($value$plusargs("TIMEOUT=%d", timeout_cycles)) begin
			$display("timeout_cycles=%0d", timeout_cycles);
		end

		if ($value$plusargs("VCD=%s", vcd_file)) begin
			$dumpfile(vcd_file);
			$dumpvars(0, test_bench);
		end

		$readmemh(program_file, mem);

		repeat (4) @(posedge clk);
		rst = 0;
	end

	always @(posedge clk) begin
		if (!rst) begin
			cycles = cycles + 1;
			if (cycles > timeout_cycles) begin
				$display("FAIL: timeout after %0d cycles at address %04x", cycles, address);
				$finish_and_return(1);
			end

			if ((read !== 1'b0) && (read !== 1'b1)) begin
				$display("FAIL: read is unknown at cycle %0d", cycles);
				$finish_and_return(1);
			end

			if (^address === 1'bx) begin
				$display("FAIL: address is unknown at cycle %0d", cycles);
				$finish_and_return(1);
			end

			if (!read) begin
				if (^dout === 1'bx) begin
					$display("FAIL: dout is unknown during write at cycle %0d address %04x", cycles, address);
					$finish_and_return(1);
				end

				case (address)
				TEST_STATUS: begin
					if (dout == 8'h00) begin
						$display("PASS: %0s in %0d cycles", program_file, cycles);
						$finish_and_return(0);
					end else begin
						$display("FAIL: %0s code=%0d at cycle %0d", program_file, dout, cycles);
						$finish_and_return(1);
					end
				end
				TEST_INTR: begin
					if (dout != 8'h00) begin
						intr <= 1'b1;
					end
				end
				TEST_PUTC: begin
					$write("%c", dout);
				end
				default: begin
					mem[address] <= dout;
				end
				endcase
			end

			if (intr && read && address == 16'h0002) begin
				intr <= 1'b0;
			end
		end
	end
endmodule

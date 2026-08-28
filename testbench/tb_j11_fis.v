`timescale 1ns/1ps

// Fast, deterministic bus for the large assembled FIS arithmetic corpus.
// The same guest harness also runs through tb_j11_cpu_io's actual SPI FRAM.
module tb_j11_fis;
	parameter UCODE_FILE = "build/j11_ucode.words";
	reg clk = 0, rst = 1, ready = 0, error = 0;
	wire req, wr, byte_access, bank;
	wire [15:0] address, wdata;
	reg [15:0] rdata = 0;
	reg [7:0] memory [0:65535];
	reg [1023:0] program_file;
	integer i, cycles, max_cycles = 10000000;
	integer fault_read = -1, fault_write = -1;
	wire injected_error = (!wr && address == fault_read) || (wr && address == fault_write);
	j11_microengine #(.UROM_WORDS(`J11_UROM_WORDS), .UCODE_FILE(UCODE_FILE)) dut (
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
			error <= (!byte_access && address[0]) || injected_error;
			if ((byte_access || !address[0]) && !injected_error) begin
				if (wr) begin
					memory[address] <= wdata[7:0];
					if (!byte_access) memory[address + 16'd1] <= wdata[15:8];
				end else rdata <= byte_access ? {8'b0, memory[address]} :
					{memory[address + 16'd1], memory[address]};
			end
		end
	end
	initial begin
		if (!$value$plusargs("PROGRAM=%s", program_file))
			$fatal(1, "Missing assembled PROGRAM");
		if ($value$plusargs("TIMEOUT=%d", max_cycles)) begin end
		if ($value$plusargs("FAULT_READ=%o", fault_read)) begin end
		if ($value$plusargs("FAULT_WRITE=%o", fault_write)) begin end
		for (i = 0; i < 65536; i = i + 1) memory[i] = 0;
		$readmemh(program_file, memory);
		repeat (4) @(negedge clk);
		rst = 0;
		for (cycles = 0; cycles < max_cycles && dut.cause_reg < 3; cycles = cycles + 1)
			@(negedge clk);
		if (dut.cause_reg != 3 || dut.jctx[0] !== 16'o012345) begin
			$display("R4=%06o CPUERR=%06o frame PC=%06o PSW=%06o data=%06o %06o %06o %06o",
				dut.jctx[4], dut.jctx[23] >> 8,
				{memory[dut.jctx[6]+1], memory[dut.jctx[6]]},
				{memory[dut.jctx[6]+3], memory[dut.jctx[6]+2]},
				{memory[16'o6001], memory[16'o6000]}, {memory[16'o6003], memory[16'o6002]},
				{memory[16'o6005], memory[16'o6004]}, {memory[16'o6007], memory[16'o6006]});
			$fatal(1, "FIS: %0s case=%0d PC=%06o IR=%06o uPC=%04h PSW=%06o R0=%06o R1=%06o R2=%06o R3=%06o SP=%06o",
				program_file, dut.jctx[5], dut.jctx[7], dut.jctx[9], dut.upc,
				dut.jctx[8], dut.jctx[0], dut.jctx[1], dut.jctx[2], dut.jctx[3], dut.jctx[6]);
		end
		$display("PASS: %0s (%0d cycles)", program_file, cycles);
		$finish;
	end
endmodule

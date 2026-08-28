`timescale 1ns/1ps

module spi_fram_model (
	input  wire cs_n,
	input  wire sck,
	input  wire mosi,
	output reg  miso
);

	localparam [2:0] PH_COMMAND = 3'd0;
	localparam [2:0] PH_ADDRESS = 3'd1;
	localparam [2:0] PH_READ    = 3'd2;
	localparam [2:0] PH_WRITE   = 3'd3;
	localparam [2:0] PH_IGNORE  = 3'd4;

	reg [7:0] memory [0:131071];
	reg [2:0] phase;
	reg [7:0] command;
	reg [7:0] input_shift;
	reg [2:0] input_count;
	reg [23:0] address;
	reg [1:0] address_count;
	reg [7:0] output_shift;
	reg [3:0] output_count;
	reg write_enable;
	reg write_started;
	// Behavioral fault controls for diagnostics; not synthesizable hardware.
	reg write_protect = 0, alias_banks = 0;
	integer transaction_count;
	integer i;

	initial begin
		for (i = 0; i < 131072; i = i + 1) begin
			memory[i] = 0;
		end
		phase = PH_COMMAND;
		command = 0;
		input_shift = 0;
		input_count = 0;
		address = 0;
		address_count = 0;
		output_shift = 0;
		output_count = 0;
		write_enable = 0;
		write_started = 0;
		transaction_count = 0;
		miso = 0;
	end

	always @(negedge cs_n) begin
		phase = PH_COMMAND;
		command = 0;
		input_shift = 0;
		input_count = 0;
		address = 0;
		address_count = 0;
		output_shift = 0;
		output_count = 0;
		write_started = 0;
		miso = 0;
		transaction_count = transaction_count + 1;
	end

	always @(posedge cs_n) begin
		if (write_started) begin
			write_enable = 0;
		end
		miso = 0;
	end

	always @(posedge sck) begin
		if (!cs_n) begin
			if (phase == PH_READ) begin
				if (output_count == 1) begin
					address = (address + 1) & 24'h01ffff;
					output_shift = memory[address[16:0]];
					output_count = 8;
				end else begin
					output_shift = {output_shift[6:0], 1'b0};
					output_count = output_count - 1'b1;
				end
			end else begin
				input_shift = {input_shift[6:0], mosi};
				if (input_count == 3'd7) begin
					input_count = 0;
					case (phase)
					PH_COMMAND: begin
						command = input_shift;
						address = 0;
						address_count = 0;
						case (input_shift)
						8'h06: begin
							write_enable = 1;
							phase = PH_IGNORE;
						end
						8'h03,
						8'h02: phase = PH_ADDRESS;
						default: phase = PH_IGNORE;
						endcase
					end
					PH_ADDRESS: begin
						address = ((address << 8) | input_shift) & 24'h01ffff;
						if (address_count == 2) begin
							if (alias_banks) address[16] = 0;
							if (command == 8'h03) begin
								phase = PH_READ;
								output_shift = memory[address[16:0]];
								output_count = 8;
							end else begin
								phase = PH_WRITE;
							end
						end else begin
							address_count = address_count + 1'b1;
						end
					end
					PH_WRITE: begin
						if (write_enable && !write_protect) begin
							memory[address[16:0]] = input_shift;
							address = (address + 1) & 24'h01ffff;
							write_started = 1;
						end
					end
					default: begin
						phase = phase;
					end
					endcase
					input_shift = 0;
				end else begin
					input_count = input_count + 1'b1;
				end
			end
		end
	end

	always @(negedge sck) begin
		if (!cs_n && phase == PH_READ) begin
			miso = output_shift[7];
		end
	end

endmodule

`timescale 1ns/1ps

// Behavioral SDHC card for the prototype, not synthesizable controller RTL.
// Independent wire-level command parser and media; delayed R1/token and busy
// exercise the firmware rather than bypassing its SD protocol.
module spi_sd_model #(
	parameter integer SECTORS = 256
) (
	input wire cs_n, sck, mosi,
	output wire miso,
	input wire absent, fail_read, fail_write, stuck_busy, bad_ocr, bad_echo, bad_status
);
	reg [7:0] memory [0:SECTORS*512-1];
	reg [7:0] write_buffer [0:511];
	reg [7:0] response [0:1023];
	reg [7:0] tx_shift = 8'hff, rx_shift = 0;
	reg [7:0] packet [0:5];
	integer bit_count = 0, packet_count = 0, head = 0, tail = 0;
	integer write_count = -1, write_lba = 0, busy_bytes = 0;
	integer command_count = 0, read_count = 0, write_commands = 0, writes = 0;
	integer init_polls = 0, power_clocks = 0, n;
	reg initialized = 0, app_command = 0, hold_busy = 0;
	reg [7:0] incoming;
	reg [31:0] argument;
	assign miso = cs_n || absent ? 1'b1 : tx_shift[7];

	task enqueue;
		input [7:0] value;
		begin response[tail] = value; tail = tail + 1; end
	endtask
	task command;
		integer c, i;
		reg previous_app;
		begin
			c = packet[0] & 63;
			argument = {packet[1], packet[2], packet[3], packet[4]};
			command_count = command_count + 1;
			head = 0; tail = 0;
			enqueue(8'hff); // nonzero Ncr
			previous_app = app_command; app_command = 0;
			case (c)
			0: begin
				if (packet[5] != 8'h95 || power_clocks < 74) $fatal(1, "SD CMD0 CRC/power clocks");
				initialized = 0; init_polls = 0; enqueue(1);
			end
			8: begin
				if (packet[5] != 8'h87 || argument != 32'h1aa) $fatal(1, "SD CMD8 CRC/argument");
				enqueue(1); enqueue(0); enqueue(0); enqueue(1); enqueue(bad_echo ? 8'h55 : 8'haa);
			end
			55: begin app_command = 1; enqueue(initialized ? 0 : 1); end
			41: begin
				if (!previous_app || argument != 32'h40000000) $fatal(1, "SD ACMD41 sequence/HCS");
				init_polls = init_polls + 1;
				if (init_polls >= 2) initialized = 1;
				enqueue(initialized ? 0 : 1);
			end
			58: begin
				enqueue(initialized ? 0 : 1);
				enqueue(bad_ocr ? 8'h80 : 8'hc0); enqueue(8'hff); enqueue(8'h80); enqueue(0);
			end
			13: begin enqueue(0); enqueue(bad_status ? 8'h04 : 8'h00); end
			17: begin
				read_count = read_count + 1;
				if (!initialized || argument >= SECTORS) enqueue(8'h20);
				else begin
					enqueue(0); enqueue(8'hff); enqueue(8'hff);
					if (fail_read) enqueue(8'h08);
					else begin
						enqueue(8'hfe);
						for (i = 0; i < 512; i = i + 1) enqueue(memory[argument*512+i]);
						enqueue(8'h12); enqueue(8'h34);
					end
				end
			end
			24: begin
				write_commands = write_commands + 1;
				if (!initialized || argument >= SECTORS) enqueue(8'h20);
				else begin enqueue(0); write_lba = argument; write_count = -2; end
			end
			default: enqueue(8'h04);
			endcase
		end
	endtask
	task consume;
		input [7:0] value;
		integer i;
		begin
			if (write_count == -2) begin
				if (value == 8'hfe) write_count = 0;
			end else if (write_count >= 0) begin
				if (write_count < 512) write_buffer[write_count] = value;
				write_count = write_count + 1;
				if (write_count == 514) begin
					write_count = -1; head = 0; tail = 0;
					enqueue(fail_write ? 8'h0d : 8'h05);
					if (!fail_write) begin
						for (i = 0; i < 512; i = i + 1) memory[write_lba*512+i] = write_buffer[i];
						writes = writes + 1;
					end
					busy_bytes = 4; hold_busy = stuck_busy;
				end
			end else if (busy_bytes == 0 && !hold_busy) begin
				if (packet_count != 0 || value[7:6] == 2'b01) begin
					packet[packet_count] = value; packet_count = packet_count + 1;
					if (packet_count == 6) begin packet_count = 0; command(); end
				end
			end
		end
	endtask
	always @(posedge cs_n) begin
		bit_count = 0; packet_count = 0; head = 0; tail = 0;
		write_count = -1; busy_bytes = 0; hold_busy = 0; tx_shift = 8'hff;
	end
	always @(posedge sck) begin
		if (cs_n) power_clocks = power_clocks + 1;
		else if (!absent) begin
			incoming = {rx_shift[6:0], mosi}; rx_shift = incoming;
			bit_count = (bit_count + 1) & 7;
			if (bit_count == 0) consume(incoming);
		end
	end
	always @(negedge sck) if (!cs_n && !absent) begin
		if (bit_count != 0) tx_shift = {tx_shift[6:0], 1'b1};
		else if (head < tail) begin tx_shift = response[head]; head = head + 1; end
		else if (hold_busy || busy_bytes != 0) begin
			tx_shift = 0;
			if (busy_bytes != 0) busy_bytes = busy_bytes - 1;
		end else tx_shift = 8'hff;
	end
endmodule

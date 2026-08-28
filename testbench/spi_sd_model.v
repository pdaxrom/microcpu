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
	// Optional diagnostic fault injection; defaults leave existing tests alone.
	reg corrupt_read_crc = 0, no_read_token = 0, never_ready = 0;
	reg [7:0] incoming;
	reg [31:0] argument;
	// Optional raw image is opened rb only. Writes use a bounded, sector-grained
	// RAM overlay; the input file is NEVER opened for writing, even on failure.
	integer image_fd = 0, image_sectors = SECTORS, dirty_count = 0;
	integer dirty_lba [0:SECTORS-1];
	reg [7:0] image_sector [0:511];
	string image_path;
	integer image_bytes, image_result;
	assign miso = cs_n || absent ? 1'b1 : tx_shift[7];
	initial begin
		if ($value$plusargs("SD_IMAGE=%s", image_path)) begin
			image_fd = $fopen(image_path, "rb");
			if (image_fd == 0) $fatal(1, "Cannot open SD image: %s", image_path);
			image_result = $fseek(image_fd, 0, 2);
			image_bytes = $ftell(image_fd);
			if (image_result != 0 || image_bytes <= 0 || image_bytes % 512 != 0)
				$fatal(1, "SD image must contain whole 512-byte sectors");
			image_sectors = image_bytes / 512;
			$display("SD image: %s (%0d sectors), read-only backing, %0d-sector RAM overlay",
				image_path, image_sectors, SECTORS);
		end
	end
	function integer overlay_slot(input integer lba);
		integer j;
		begin
			overlay_slot = -1;
			for (j = 0; j < dirty_count; j = j + 1)
				if (dirty_lba[j] == lba) overlay_slot = j;
		end
	endfunction
	task load_sector(input integer lba);
		integer slot, j, result;
		begin
			slot = image_fd != 0 ? overlay_slot(lba) : lba;
			if (slot >= 0) begin
				for (j = 0; j < 512; j = j + 1) image_sector[j] = memory[slot*512+j];
			end else begin
				result = $fseek(image_fd, lba*512, 0);
				if (result != 0) $fatal(1, "SD image seek failed: LBA %0d", lba);
				result = $fread(image_sector, image_fd);
				if (result != 512) $fatal(1, "SD image short read: LBA %0d", lba);
			end
		end
	endtask
	task store_sector(input integer lba);
		integer slot, j;
		begin
			slot = image_fd != 0 ? overlay_slot(lba) : lba;
			if (slot < 0) begin
				if (dirty_count == SECTORS) $fatal(1, "SD RAM overlay full");
				slot = dirty_count; dirty_count = dirty_count + 1;
				dirty_lba[slot] = lba;
			end
			for (j = 0; j < 512; j = j + 1) memory[slot*512+j] = write_buffer[j];
		end
	endtask

	task enqueue;
		input [7:0] value;
		begin response[tail] = value; tail = tail + 1; end
	endtask
	task command;
		integer c, i;
		reg previous_app;
		reg [15:0] block_crc;
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
				if (init_polls >= 2 && !never_ready) initialized = 1;
				enqueue(initialized ? 0 : 1);
			end
			58: begin
				enqueue(initialized ? 0 : 1);
				enqueue(bad_ocr ? 8'h80 : 8'hc0); enqueue(8'hff); enqueue(8'h80); enqueue(0);
			end
			13: begin enqueue(0); enqueue(bad_status ? 8'h04 : 8'h00); end
			17: begin
				read_count = read_count + 1;
				if (!initialized || argument >= image_sectors) enqueue(8'h20);
				else begin
					enqueue(0); enqueue(8'hff); enqueue(8'hff);
					if (fail_read) enqueue(8'h08);
					else if (!no_read_token) begin
						load_sector(argument);
						enqueue(8'hfe);
						block_crc = 0;
						for (i = 0; i < 512; i = i + 1) begin
							enqueue(image_sector[i]);
							block_crc = crc16_byte(block_crc, image_sector[i]);
						end
						enqueue(block_crc[15:8]);
						enqueue(block_crc[7:0] ^ {7'b0, corrupt_read_crc});
					end
				end
			end
			24: begin
				write_commands = write_commands + 1;
				if (!initialized || argument >= image_sectors) enqueue(8'h20);
				else begin enqueue(0); write_lba = argument; write_count = -2; end
			end
			default: enqueue(8'h04);
			endcase
		end
	endtask
	function [15:0] crc16_byte(input [15:0] crc, input [7:0] data);
		integer bit_index;
		reg [15:0] value;
		begin
			value = crc;
			for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1)
				value = {value[14:0], 1'b0} ^
					((value[15] ^ data[bit_index]) ? 16'h1021 : 16'h0000);
			crc16_byte = value;
		end
	endfunction
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
						store_sector(write_lba);
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

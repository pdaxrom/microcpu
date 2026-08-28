`timescale 1ns/1ps

// Actual board top and serial pins. The PDP-11 fixture is assembled by
// microasm11, placed only on the SD model, and loaded by the real bootstrap.
module tb_boot_trace;
	parameter integer TICK_DIVISOR = 532000;
	reg res = 1, rx = 1;
	wire tx, fram_cs, fram_sck, fram_mosi, fram_miso;
	wire sd_cs, sd_sck, sd_mosi, sd_miso;
	integer scenario = 0, cycles = 0, bit_index, i, j, sector;
	integer banners = 0, verified = 0, disk_done = 0, failures = 0, stopped = 0;
	integer cache_bad = 0, dma_bad = 0, crc_bad = 0, records = 0, guest_fetches = 0;
	integer before_quiet, parsed, held_reads, resets = 0;
	reg guest_tx_seen = 0;
	reg [7:0] received;
	reg [15:0] f [0:14];
	string line_buffer = "", tag;
	ucode_sd_microcomp #(.UCODE_FILE("../boards/hc1200-microcomp/j11_boot_trace.mem"), .TICK_DIVISOR(TICK_DIVISOR)) board (
		.res(res), .rx(rx), .tx(tx), .gpio_mosi(fram_mosi),
		.gpio_miso(fram_miso), .gpio_msck(fram_sck), .gpio_mcs(fram_cs),
		.sd_cs_n(sd_cs), .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_miso(sd_miso),
		.gpio_din(), .gpio_ce(), .gpio_clk(), .gpio_rs(), .gpio_blank(),
		.gpio_reg_latch(), .gpio_key_row(4'b1111)
	);
	spi_fram_model fram (.cs_n(fram_cs), .sck(fram_sck), .mosi(fram_mosi), .miso(fram_miso));
	spi_sd_model card (
		.cs_n(sd_cs), .sck(sd_sck), .mosi(sd_mosi), .miso(sd_miso),
		.absent(scenario == 1), .fail_read(scenario == 10 || (scenario == 2 && card.read_count == 1)),
		.fail_write(scenario == 11), .stuck_busy(1'b0), .bad_ocr(scenario == 8),
		.bad_echo(scenario == 7), .bad_status(1'b0)
	);
	`define J11_CONTEXT_ENGINE board.engine
	`include "include/j11_context_probe.vh"
	always @(negedge board.clk) begin
		cycles = cycles + 1;
		if (cycles > 150000000)
			$fatal(1, "Trace timeout case=%0d uPC=%04h cause=%0d PC=%06o line=%s",
				scenario, board.debug_upc, board.debug_cause, context_words[7], line_buffer);
		fram.write_protect = scenario == 4 || (scenario == 5 && !board.guest_bus.bank_override);
		card.corrupt_read_crc = scenario == 3 || (scenario == 12 && guest_tx_seen);
		if (card.writes || (card.write_commands && scenario != 11)) $fatal(1, "Unexpected SD write");
	end
	always @(posedge board.clk) if (!board.reset) begin
		if (board.guest_reset) resets = resets + 1;
		if (board.engine.state == board.engine.ST_EXEC && board.engine.context_write_enable && board.engine.context_write_address == 9) begin
			if (scenario > 0 && scenario < 11) $fatal(1, "Guest fetch after failed bootstrap");
			if (guest_fetches == 0) begin
				if (verified != 2 || disk_done != 1 || card.read_count != 2 || board.guest_bus.bank_override)
					$fatal(1, "Guest started before two CRC/FRAM checks and DMA completion");
				if (context_words[0] !== 0 || context_words[1] !== 16'o177440 ||
					context_words[2] !== 0 || context_words[3] !== 0 || context_words[4] !== 16'o2020 ||
					context_words[5] !== 0 || context_words[6] !== 16'o2000 || context_words[7] !== 0 || context_words[8] !== 4)
					$fatal(1, "Tracing corrupted the cold boot register ABI");
				for (sector = 0; sector < 2; sector = sector + 1)
					for (j = 0; j < 512; j = j + 1)
						if (fram.memory[sector*512+j] !== card.memory[sector*512+j])
							$fatal(1, "Boot sector mismatch in guest FRAM");
			end
			guest_fetches = guest_fetches + 1;
		end
	end

	// Verify 115200 8N1 from the actual TX pin, including every stop bit.
	initial forever begin
		@(negedge tx);
		repeat (345) @(negedge board.clk);
		for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
			received[bit_index] = tx;
			repeat (230) @(negedge board.clk);
		end
		if (tx !== 1) $fatal(1, "Trace UART framing error");
		if (received == "U" && line_buffer == "" && (scenario == 0 || scenario >= 11)) guest_tx_seen = 1;
		else if (received == 10) begin
			if (line_buffer != "") $display("UART: %s", line_buffer);
			if (line_buffer == "J11 TRACE NOFIS") begin
				banners = banners + 1;
				if (fram.transaction_count != 0 || card.command_count != 0)
					$fatal(1, "Banner must precede external memory/card use");
			end else if (line_buffer != "") begin
				parsed = $sscanf(line_buffer, "%s %h %h %h %h %h %h %h %h %h %h %h %h %h %h %h",
					tag, f[0], f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[8], f[9], f[10], f[11], f[12], f[13], f[14]);
				if (parsed != 16 || line_buffer.len() != 76) $fatal(1, "Malformed trace record");
				records = records + 1;
				if (tag == "V") begin
					if (f[13] !== f[14]) $fatal(1, "False CRC PASS");
					verified = verified + 1;
				end
				if (tag == "D" && f[4] == 16'h0090 && f[5] == 0 && f[6] == 1024 && f[7] == 0) disk_done = disk_done + 1;
				if (tag == "E") begin
					if (scenario >= 11 && (!guest_tx_seen || !f[0][15])) $fatal(1, "Runtime failure must remain visible after guest TX");
					failures = failures + 1;
				end
				if (tag == "X") begin
					if (f[13] === f[14]) $fatal(1, "False CRC mismatch");
					crc_bad = crc_bad + 1;
				end
				if (tag == "K") cache_bad = cache_bad + 1;
				if (tag == "M") dma_bad = dma_bad + 1;
				if (tag == "K" || tag == "M")
					if (f[13] === f[14] || f[12] != 6) $fatal(1, "Bad FRAM failure details");
				if (tag == "G" && f[12] >= 3) stopped = stopped + 1;
			end
			line_buffer = "";
		end else if (received != 13) line_buffer = {line_buffer, received};
	end
	task send_byte(input [7:0] value);
		integer b;
		begin
			@(negedge board.clk); rx = 0;
			repeat (230) @(negedge board.clk);
			for (b = 0; b < 8; b = b + 1) begin
				rx = value[b]; repeat (230) @(negedge board.clk);
			end
			rx = 1; repeat (230) @(negedge board.clk);
		end
	endtask
	initial begin
		if ($value$plusargs("SCENARIO=%d", scenario)) begin end
		if (scenario < 0 || scenario > 12) $fatal(1, "Unknown boot trace case");
		#1;
		if (card.image_fd != 0) $fatal(1, "Use assembled synthetic boot image");
		if (scenario >= 11) $readmemh("build/guest_boot_trace_runtime_error.hex", card.memory);
		else $readmemh("build/guest_sd_cold_boot_uart.hex", card.memory);
		for (i = 0; i < 131072; i = i + 1) fram.memory[i] = 8'ha5;
		card.no_read_token = scenario == 6;
		card.never_ready = scenario == 9;
		if (scenario == 0) begin
			wait (guest_tx_seen);
			before_quiet = records;
			// More than one heartbeat interval in the guest RX wait loop:
			// tracing must stop without consuming UART RX or altering guest state.
			repeat (TICK_DIVISOR * 60) @(negedge board.clk);
			if (records != before_quiet) $fatal(1, "Trace polluted the active guest console");
			send_byte("Z");
			wait (stopped != 0);
			if (board.debug_cause != 3 || context_words[0] !== 16'o12345 || context_words[2] !== "Z" ||
				context_words[3] !== 2 || guest_fetches == 0 || resets != 1 || card.read_count != 2 ||
				failures || cache_bad || dma_bad || crc_bad)
				$fatal(1, "Guest RESET/WAIT/UART/HALT or transparent tracing failed");
		end else if (scenario >= 11) begin
			wait (stopped != 0);
			if (!guest_tx_seen || board.debug_cause != 3 || context_words[0] !== 16'o12345 ||
				context_words[3] !== 1 ||
				context_words[2] !== (scenario == 11 ? 2 : 1) || failures != 1 || cache_bad || dma_bad ||
				crc_bad != (scenario == 12 ? 1 : 0) || board.guest_bus.bank_override || !sd_cs ||
				card.write_commands != (scenario == 11 ? 1 : 0))
				$fatal(1, "Quiet-console runtime SD failure did not report/return safely");
		end else begin
			wait (stopped != 0);
			if (guest_fetches != 0 || board.guest_bus.bank_override || !sd_cs || sd_sck)
				$fatal(1, "Failed bootstrap did not remain safely stopped");
			if (scenario == 4 || scenario == 5) begin
				if (board.debug_cause != 6 || cache_bad != (scenario == 4 ? 1 : 0) || dma_bad != (scenario == 5 ? 1 : 0))
					$fatal(1, "Missing cache/DMA readback failure");
			end else if (board.debug_cause != 5 || failures != 1 || crc_bad != (scenario == 3 ? 1 : 0))
				$fatal(1, "Missing SD error details");
			if (scenario == 2 && (verified != 1 || context_words[41] !== 16'hff00 || fram.memory[512] !== 8'ha5))
				$fatal(1, "Second sector failure lost partial DMA status");
			if (scenario == 3 && (context_words[41] !== 16'hfe00 || fram.memory[0] !== 8'ha5))
				$fatal(1, "Bad-CRC cache was copied into guest RAM");
		end
		held_reads = card.read_count;
		wait (stopped == 2);
		if (card.read_count != held_reads || banners != 1) $fatal(1, "Stop heartbeat restarted the disk");
		$display("PASS: boot trace case %0d, real UART/CRC/FRAM/stop diagnostics (%0d clocks)", scenario, cycles);
		$finish;
	end
endmodule

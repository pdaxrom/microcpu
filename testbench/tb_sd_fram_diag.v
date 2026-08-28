`timescale 1ns/1ps

// Real board top, power-on reset, native firmware and UART pins. Only the
// oscillator and external SPI devices are modeled; no CPU/guest deposits.
module tb_sd_fram_diag;
	parameter UCODE_FILE = "../boards/hc1200-microcomp/sd_fram_diag.mem";
	parameter integer TICK_DIVISOR = 532000;
	reg res = 1, rx = 1;
	wire tx, fram_cs, fram_sck, fram_mosi, fram_miso;
	wire sd_cs, sd_sck, sd_mosi, sd_miso;
	integer scenario = 0, cycles = 0, i, bit_index;
	integer menus = 0, banners = 0, crc_passes = 0, sd_failures = 0;
	integer rw_passes = 0, rw_failures = 0, restores = 0, memory_writes = 0;
	integer reads_before_retry, failures_before_retry, menus_before_retry;
	reg permit_write = 0, expect_echo = 0, echoed = 0, recovering = 0;
	reg [7:0] received;
	reg [15:0] crc_vector;
	string line_buffer = "";
	ucode_sd_microcomp #(.UCODE_FILE(UCODE_FILE), .TICK_DIVISOR(TICK_DIVISOR)) board (
		.res(res), .rx(rx), .tx(tx), .gpio_mosi(fram_mosi),
		.gpio_miso(fram_miso), .gpio_msck(fram_sck), .gpio_mcs(fram_cs),
		.sd_cs_n(sd_cs), .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_miso(sd_miso),
		.gpio_din(), .gpio_ce(), .gpio_clk(), .gpio_rs(), .gpio_blank(),
		.gpio_reg_latch(), .gpio_key_row(4'b1111)
	);
	spi_fram_model fram (
		.cs_n(scenario == 8 ? 1'b1 : fram_cs), .sck(fram_sck),
		.mosi(fram_mosi), .miso(fram_miso)
	);
	spi_sd_model card (
		.cs_n(sd_cs), .sck(sd_sck), .mosi(sd_mosi), .miso(sd_miso),
		.absent(scenario == 1 && !recovering), .fail_read(scenario == 5),
		.fail_write(1'b0), .stuck_busy(1'b0), .bad_ocr(scenario == 3),
		.bad_echo(scenario == 2), .bad_status(1'b0)
	);
	always @(negedge board.clk) begin
		cycles = cycles + 1;
		if (cycles > 150000000)
			$fatal(1, "Diagnostic watchdog case=%0d uPC=%04h line=%s", scenario, board.debug_upc, line_buffer);
		if (!board.reset && board.debug_cause != 0)
			$fatal(1, "Unexpected native bus fault uPC=%04h", board.debug_upc);
		if (board.guest_req && board.guest_write &&
			(board.guest_address < 16'he000 || board.guest_bus.bank_override) &&
			board.guest_address != 16'hf00c) begin
			if (!permit_write) $fatal(1, "FRAM write before explicit W command");
			if (board.guest_address < 16'h0200 || board.guest_address > 16'h0207)
				$fatal(1, "FRAM write outside reserved diagnostic scratch");
			memory_writes = memory_writes + 1;
		end
		if (card.write_commands || card.writes) $fatal(1, "Diagnostic issued a disk write");
		card.corrupt_read_crc = scenario == 4 || (scenario == 11 && card.read_count >= 1);
	end

	// Decode 115200 8N1 from the actual package TX signal (230 clocks/bit).
	initial forever begin
		@(negedge tx);
		repeat (345) @(negedge board.clk);
		for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
			received[bit_index] = tx;
			repeat (230) @(negedge board.clk);
		end
		if (tx !== 1) $fatal(1, "UART stop bit/baud mismatch");
		if (expect_echo && received == "Z") begin
			echoed = 1;
			expect_echo = 0;
		end else if (received == 10) begin
			$display("UART: %s", line_buffer);
			if (line_buffer == "HC1200 DIAG 115200 8N1") banners = banners + 1;
			if (line_buffer == "ALIVE R=read W=FRAM-write") menus = menus + 1;
			if (line_buffer == "CRC=D594/D594 PASS") crc_passes = crc_passes + 1;
			if (line_buffer.len() >= 7 && line_buffer.substr(0, 6) == "SD FAIL")
				sd_failures = sd_failures + 1;
			if (line_buffer == "FRAM R/W PASS") rw_passes = rw_passes + 1;
			if (line_buffer == "FRAM R/W FAIL") rw_failures = rw_failures + 1;
			if (line_buffer == "FRAM RESTORE PASS") restores = restores + 1;
			line_buffer = "";
		end else if (received != 13) line_buffer = {line_buffer, received};
	end

	task send_byte(input [7:0] value);
		integer bit_number;
		begin
			@(negedge board.clk); rx = 0;
			repeat (230) @(negedge board.clk);
			for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
				rx = value[bit_number];
				repeat (230) @(negedge board.clk);
			end
			rx = 1;
			repeat (230) @(negedge board.clk);
		end
	endtask

	initial begin
		if ($value$plusargs("SCENARIO=%d", scenario)) begin end
		if (scenario < 0 || scenario > 11) $fatal(1, "Unknown diagnostic scenario");
		#1;
		if (card.image_fd != 0) $fatal(1, "Use the synthetic CRC fixture, not SD_IMAGE");
		for (i = 0; i < 512; i = i + 1) card.memory[i] = 8'(i * 37 + 11);
		for (i = 0; i < 131072; i = i + 1) fram.memory[i] = 8'(i * 13 + (i >> 16) * 37 + 7);
		fram.write_protect = scenario == 9;
		fram.alias_banks = scenario == 10;
		card.no_read_token = scenario == 7;
		card.never_ready = scenario == 6;
		// SD Association's published 512 x FF vector, independent of firmware.
		crc_vector = 0;
		for (i = 0; i < 512; i = i + 1) crc_vector = card.crc16_byte(crc_vector, 8'hff);
		if (crc_vector != 16'h7fa1) $fatal(1, "SD model CRC16 reference vector");
		wait (menus == 1);
		if (banners != 1 || !sd_cs || sd_sck || board.guest_bus.bank_override)
			$fatal(1, "Banner or error cleanup is missing");
		if (scenario == 0 || scenario >= 8 && scenario <= 10) begin
			if (crc_passes != 2 || sd_failures != 0 || card.read_count != 2)
				$fatal(1, "Expected correct SD initialization, slow and fast CRC checks");
		end else begin
			if (sd_failures != 1 || crc_passes != (scenario == 11 ? 1 : 0))
				$fatal(1, "SD fault was not reported correctly");
		end
		if (memory_writes != 0) $fatal(1, "Power-on diagnostic was not read-only");
		// Wait for a heartbeat with no user input; a late-opened terminal sees it.
		wait (menus == 2);
		expect_echo = 1;
		send_byte("Z");
		wait (echoed);
		// Once explicitly authorized from RX, FRAM tests must restore every byte.
		permit_write = 1;
		send_byte("W");
		wait (restores == 1);
		if (scenario >= 8 && scenario <= 10) begin
			if (rw_failures != 1 || rw_passes != 0) $fatal(1, "Missing FRAM failure report");
		end else if (rw_passes != 1 || rw_failures != 0) $fatal(1, "FRAM word/byte test failed");
		for (i = 0; i < 131072; i = i + 1)
			if (fram.memory[i] !== 8'(i * 13 + (i >> 16) * 37 + 7))
				$fatal(1, "FRAM restore/collateral damage at %05h", i);
		if (board.guest_bus.bank_override || !fram_cs || !sd_cs) $fatal(1, "Bus not released");
		if (scenario == 1) begin
			// Insert the card and retry from the terminal without reprogramming.
			wait (menus == 3);
			reads_before_retry = card.read_count;
			failures_before_retry = sd_failures;
			menus_before_retry = menus;
			recovering = 1;
			permit_write = 0;
			send_byte("r");
			wait (menus > menus_before_retry);
			if (banners != 2 || crc_passes != 2 || sd_failures != failures_before_retry ||
				card.read_count != reads_before_retry + 2) $fatal(1, "Card insertion/R retry failed");
		end
		$display("PASS: native diagnostic scenario %0d, UART/heartbeat/SD/FRAM (%0d clocks)", scenario, cycles);
		$finish;
	end
endmodule

`timescale 1ns/1ps

// Use the actual board top, including its power-on reset synchronizer.
// Only OSCH and the two external SPI devices are models. No guest deposits.
module tb_sd_cold_boot;
	parameter UCODE_FILE = "build/j11_sd_boot.words";
	reg res = 1; // no external reset pulse at power-on
	integer scenario = 0, cycles = 0, first_fetches = 0, resets = 0;
	integer i, j, sector, read_base = 0, last_tick = 0, ticks_seen = 0;
	reg [15:0] previous_ticks = 0;
	reg was_reset = 1;
	wire fram_cs, fram_sck, fram_mosi, fram_miso;
	wire sd_cs, sd_sck, sd_mosi, sd_miso;
	ucode_sd_microcomp #(.UCODE_FILE(UCODE_FILE)) board (
		.res(res), .rx(1'b1), .tx(), .gpio(), .gpio_mosi(fram_mosi),
		.gpio_miso(fram_miso), .gpio_msck(fram_sck), .gpio_mcs(fram_cs),
		.sd_cs_n(sd_cs), .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_miso(sd_miso),
		.gpio_din(), .gpio_ce(), .gpio_clk(), .gpio_rs(), .gpio_blank(),
		.gpio_reg_latch(), .gpio_key_row(4'b1111)
	);
	spi_fram_model fram (.cs_n(fram_cs), .sck(fram_sck), .mosi(fram_mosi), .miso(fram_miso));
	spi_sd_model card (.cs_n(sd_cs), .sck(sd_sck), .mosi(sd_mosi), .miso(sd_miso),
		.absent(scenario == 1), .fail_read(scenario == 2 || (scenario == 3 && card.read_count == 1)),
		.fail_write(1'b0), .stuck_busy(1'b0), .bad_ocr(scenario == 4),
		.bad_echo(scenario == 5), .bad_status(1'b0));
	`define J11_CONTEXT_ENGINE board.engine
	`include "include/j11_context_probe.vh"

	always @(negedge board.clk) begin
		cycles = cycles + 1;
		if (cycles > 10000000)
			$fatal(1, "Cold boot timeout scenario=%0d cause=%0d PC=%06o uPC=%04h",
				scenario, board.debug_cause, context_words[7], board.debug_upc);
		if (board.reset || was_reset) begin
			last_tick = cycles;
			previous_ticks = 0;
		end else if (board.guest_bus.base.ticks != previous_ticks) begin
			if (cycles - last_tick != 532000 || board.guest_bus.base.ticks != previous_ticks + 16'd1)
				$fatal(1, "50-Hz tick interval changed, including across guest RESET");
			last_tick = cycles;
			previous_ticks = board.guest_bus.base.ticks;
			ticks_seen = ticks_seen + 1;
		end
		was_reset = board.reset;
	end
	always @(posedge board.clk) if (!board.reset) begin
		if (board.guest_reset) resets = resets + 1;
		if (board.engine.state == board.engine.ST_EXEC && board.engine.context_write_enable &&
			board.engine.context_write_address == 9) begin
			if (scenario > 0 && scenario < 6) $fatal(1, "Executed stale/partial FRAM after failed SD boot");
			if (first_fetches == 0) begin
				if (card.read_count != read_base + 2 || card.writes != 0 || board.guest_bus.bank_override || !sd_cs)
					$fatal(1, "First guest instruction preceded successful two-sector boot");
				if (context_words[0] !== 0 || context_words[1] !== 16'o177440 ||
					context_words[2] !== 0 || context_words[3] !== 0 || context_words[4] !== 16'o2020 ||
					context_words[5] !== 0 || context_words[6] !== 16'o2000 ||
					context_words[7] !== 0 || context_words[8] !== 4)
					$fatal(1, "Cold boot register ABI mismatch");
				for (sector = 0; sector < 2; sector = sector + 1) begin
					card.load_sector(sector);
					for (j = 0; j < 512; j = j + 1)
						if (fram.memory[sector*512+j] !== card.image_sector[j])
							$fatal(1, "Cold boot disk/FRAM mismatch at %0d", sector*512+j);
				end
			end
			first_fetches = first_fetches + 1;
		end
	end
	task await_success;
		begin
			wait (board.debug_cause == 3 || board.debug_cause == 4 || board.debug_cause == 5);
			if (board.debug_cause != 3 || context_words[0] !== 16'o12345 ||
				first_fetches == 0 || resets != 1 || context_words[3] !== 2 || ticks_seen < 2)
				$fatal(1, "Boot/RESET/WAIT failure cause=%0d R0=%06o PC=%06o resets=%0d clockIRQs=%0d",
					board.debug_cause, context_words[0], context_words[7], resets, context_words[3]);
			if (card.read_count != read_base + 2 || card.write_commands != 0 || board.guest_bus.bank_override)
				$fatal(1, "Guest RESET restarted SD or boot wrote to disk");
		end
	endtask
	initial begin
		if ($value$plusargs("SCENARIO=%d", scenario)) begin end
		if (scenario < 0 || scenario > 6) $fatal(1, "Unknown cold boot scenario");
		#1;
		if (card.image_fd != 0) $fatal(1, "Cold boot smoke uses its assembled synthetic SD, not SD_IMAGE");
		$readmemh("build/guest_sd_cold_boot.hex", card.memory);
		// Zero FRAM for the main path; hostile stale data for all other cases.
		for (i = 0; i < 131072; i = i + 1) fram.memory[i] = scenario == 0 ? 0 : 8'ha5;
		if (scenario > 0 && scenario < 6) begin
			wait (board.debug_cause == 5);
			if (!context_words[40][15] || context_words[41] == 0 || first_fetches != 0 ||
				board.guest_bus.bank_override || !sd_cs || sd_sck || card.writes != 0)
				$fatal(1, "Failed boot did not stop safely with RH error status");
			repeat (10000) @(negedge board.clk);
			if (first_fetches != 0 || board.debug_cause != 5) $fatal(1, "Failed boot escaped stop loop");
			if (scenario == 3) begin
				if (card.read_count != 2 || context_words[41] !== 16'hff00 ||
					fram.memory[0] !== card.memory[0] || fram.memory[512] !== 8'ha5)
					$fatal(1, "Second-sector failure did not retain partial DMA status");
			end
			$display("PASS: SD cold boot error scenario %0d stops before any guest fetch", scenario);
			// Inserting/fixing the card and pressing board reset must retry.
			read_base = card.read_count;
			scenario = 0;
			res = 0;
			repeat (4) @(negedge board.clk);
			res = 1;
		end
		await_success();
		$display("PASS: board power-on/SD boot, guest RESET, two 50-Hz WAIT interrupts (%0d clocks)", cycles);
		$finish;
	end
endmodule

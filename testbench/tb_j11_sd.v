`timescale 1ns/1ps
module tb_j11_sd;
	parameter integer WORDS = `J11_UROM_WORDS;
	parameter UCODE_FILE = "build/j11_sd.words";
	reg clk = 0, rst = 1;
	wire req, wr, byte_access, bank, ready, error, reset_guest;
	wire [15:0] address, wdata, rdata;
	wire bus_ready, bus_error, bus_irq;
	wire [2:0] irq_level;
	wire [7:0] irq_vector;
	wire fram_cs, fram_sck, fram_mosi, fram_miso, sd_cs, sd_sck, sd_mosi, sd_miso;
	integer scenario = 0, i, sector, word_index, cycles;
	reg [15:0] pattern;
	reg [1023:0] program_file;
	integer custom_program = 0;
	wire injected_fault = req && ((scenario == 7 && !wr && address == 16'o6002 && !bus.bank_override) ||
		(scenario == 10 && wr && address == 2 && bus.bank_override && card.read_count == 2));
	assign ready = injected_fault || bus_ready;
	assign error = injected_fault || bus_error;
	ucode_cpu #(.UROM_WORDS(WORDS), .UCODE_FILE(UCODE_FILE)) dut (
		.clk(clk), .rst(rst), .guest_req(req), .guest_write(wr), .guest_byte(byte_access),
		.guest_bank(bank), .guest_address(address), .guest_wdata(wdata), .guest_rdata(rdata),
		.guest_ready(ready), .guest_error(error), .irq(bus_irq), .irq_level(irq_level),
		.irq_vector(irq_vector), .guest_reset(reset_guest)
	);
	ucode_sd_guest_bus #(.FRAM_CLK_DIV(1), .TICK_DIVISOR(1000), .SD_SLOW_DIV(3), .SD_FAST_DIV(1)) bus (
		.clk(clk), .rst(rst), .guest_reset(reset_guest), .req(req && !injected_fault),
		.write(wr), .byte_access(byte_access), .bank(bank), .address(address), .wdata(wdata),
		.rdata(rdata), .ready(bus_ready), .error(bus_error), .busy(), .uart_rx(1'b1), .uart_tx(),
		.irq(bus_irq), .irq_level(irq_level), .irq_vector(irq_vector),
		.spi_cs_n(fram_cs), .spi_sck(fram_sck), .spi_mosi(fram_mosi), .spi_miso(fram_miso),
		.sd_cs_n(sd_cs), .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_miso(sd_miso)
	);
	spi_fram_model fram (.cs_n(fram_cs), .sck(fram_sck), .mosi(fram_mosi), .miso(fram_miso));
	spi_sd_model card (.cs_n(sd_cs), .sck(sd_sck), .mosi(sd_mosi), .miso(sd_miso),
		.absent(scenario == 1), .fail_read(scenario == 2), .fail_write(scenario == 3),
		.stuck_busy(scenario == 4), .bad_ocr(scenario == 5), .bad_echo(scenario == 6), .bad_status(scenario == 9));
	`define J11_CONTEXT_ENGINE dut
	`include "include/j11_context_probe.vh"
	always #5 clk = !clk;
	reg held = 0;
	reg [34:0] held_request;
	always @(negedge clk) if (!rst) begin
		if (bus.spi_busy && bus.base.fram_busy) $fatal(1, "Competing SPI/FRAM masters");
		if (bus.bank_override && req && address < 16'he000 && address >= 512)
			$fatal(1, "DMA escaped the reserved FRAM cache");
		if (req && !ready) begin
			if (held && held_request !== {wr, byte_access, bank, address, wdata})
				$fatal(1, "Guest/DMA request changed while waiting");
			held = 1; held_request = {wr, byte_access, bank, address, wdata};
		end else held = 0;
	end
	initial begin
		if ($value$plusargs("SCENARIO=%d", scenario)) begin end
		program_file = scenario == 0 ? "build/guest_rh11_disk.hex" : "build/guest_rh11_disk_error.hex";
		custom_program = $value$plusargs("PROGRAM=%s", program_file);
		for (i = 0; i < 131072; i = i + 1) fram.memory[i] = 0;
		for (sector = 0; sector < 256; sector = sector + 1)
			for (word_index = 0; word_index < 256; word_index = word_index + 1) begin
				pattern = (sector << 8) ^ word_index ^ 16'ha55a;
				card.memory[sector*512+word_index*2] = pattern[7:0];
				card.memory[sector*512+word_index*2+1] = pattern[15:8];
			end
		$readmemh(program_file, fram.memory);
		fram.memory[16'o14002] = scenario;
		repeat (4) @(negedge clk); rst = 0;
		for (cycles = 0; cycles < 8000000 && dut.cause_reg != 3; cycles = cycles + 1)
			@(negedge clk);
		if (dut.cause_reg != 3 || context_words[0] !== 16'o12345)
			$fatal(1, "Disk scenario=%0d guest case=%0d PC=%06o uPC=%h cause=%h CS1=%h WC=%h BA=%h CS2=%h ER=%h flags=%h",
				scenario, context_words[5], context_words[7], dut.upc, dut.cause_reg,
				context_words[40], context_words[41], context_words[42], context_words[44], context_words[46], context_words[56]);
		if (bus.bank_override || !sd_cs || sd_sck) $fatal(1, "Completion left private bank/card active");
		if (custom_program) begin
			$display("PASS: %0s on full SD/FRAM bus (%0d clocks)", program_file, cycles);
			$finish;
		end
		if (scenario == 8 && card.argument != 32'd4325375) $fatal(1, "24-bit RK LBA calculation");
		// Entire media comparison catches lost tails, wrong LBA and accidental writes.
		for (sector = 0; sector < 256; sector = sector + 1) begin
			card.load_sector(sector);
			for (word_index = 0; word_index < 256; word_index = word_index + 1) begin
				pattern = (sector << 8) ^ word_index ^ 16'ha55a;
				if (scenario == 0 && sector == 21 && word_index == 0) pattern = 16'o12345;
				if (scenario == 0 && sector == 21 && word_index == 1) pattern = 16'o67770;
				if ((scenario == 4 || scenario == 7 || scenario == 9) && sector == 0 && word_index == 0) pattern = 16'o12345;
				if ((scenario == 4 || scenario == 9) && sector == 0 && word_index == 1) pattern = 16'o67770;
				if (scenario == 10 && sector == 0) pattern = word_index == 0 ? 16'o12345 :
					word_index == 1 ? 16'o67770 : 16'b0;
				if ({card.image_sector[word_index*2+1], card.image_sector[word_index*2]} !== pattern)
					$fatal(1, "Media mismatch sector=%0d word=%0d", sector, word_index);
			end
		end
		$display("PASS: RK611/SD scenario %0d; %0d clocks, commands=%0d reads=%0d writes=%0d", scenario, cycles,
			card.command_count, card.read_count, card.writes);
		$finish;
	end
endmodule

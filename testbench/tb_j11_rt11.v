`timescale 1ns/1ps

// Integration boot: real microengine, native services, serial UART and both
// wire-level SPI devices. FRAM starts empty; the uROM cold-start code boots SD.
module tb_j11_rt11;
	parameter UCODE_FILE = "build/j11_sd_boot.words";
	reg clk = 0, rst = 1, rx = 1;
	wire req, wr, byte_access, bank, ready, error, guest_reset, irq;
	wire [2:0] irq_level;
	wire [7:0] irq_vector;
	wire [15:0] address, wdata, rdata;
	wire tx, fram_cs, fram_sck, fram_mosi, fram_miso;
	wire sd_cs, sd_sck, sd_mosi, sd_miso;
	integer cycles = 0, max_cycles = 2000000000, tx_count = 0, last_tx = 0;
	integer console_fd, trace_fd = 0, bit_index, stage = 0;
	integer previous_prompt_tx = -1, rx_sent = 0, rx_reads = 0;
	integer bootstrap_sector, bootstrap_byte;
	reg startup_script_done = 0;
	reg [7:0] tx_byte;
	string line = "", console_path = "build/rt11_console.log", trace_path;
	ucode_cpu #(.UROM_WORDS(`J11_UROM_WORDS), .UCODE_FILE(UCODE_FILE)) dut (
		.clk(clk), .rst(rst), .guest_req(req), .guest_write(wr), .guest_byte(byte_access),
		.guest_bank(bank), .guest_address(address), .guest_wdata(wdata), .guest_rdata(rdata),
		.guest_ready(ready), .guest_error(error), .irq(irq), .irq_level(irq_level),
		.irq_vector(irq_vector), .guest_reset(guest_reset),
		.debug_upc(), .debug_guest_r0(), .debug_guest_pc(), .debug_guest_psw(),
		.debug_guest_ir(), .debug_cause(), .debug_pending_irq()
	);
	// Board divisors, including 50-Hz native time at the 26.6-MHz clock.
	ucode_sd_guest_bus bus (
		.clk(clk), .rst(rst), .guest_reset(guest_reset), .req(req), .write(wr),
		.byte_access(byte_access), .bank(bank), .address(address), .wdata(wdata),
		.rdata(rdata), .ready(ready), .error(error), .busy(), .uart_rx(rx), .uart_tx(tx),
		.irq(irq), .irq_level(irq_level), .irq_vector(irq_vector),
		.spi_cs_n(fram_cs), .spi_sck(fram_sck), .spi_mosi(fram_mosi), .spi_miso(fram_miso),
		.sd_cs_n(sd_cs), .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_miso(sd_miso)
	);
	spi_fram_model fram (.cs_n(fram_cs), .sck(fram_sck), .mosi(fram_mosi), .miso(fram_miso));
	spi_sd_model card (.cs_n(sd_cs), .sck(sd_sck), .mosi(sd_mosi), .miso(sd_miso),
		.absent(1'b0), .fail_read(1'b0), .fail_write(1'b0), .stuck_busy(1'b0),
		.bad_ocr(1'b0), .bad_echo(1'b0), .bad_status(1'b0));
	`define J11_CONTEXT_ENGINE dut
	`include "include/j11_context_probe.vh"
	always #5 clk = !clk; // cycles use board divisors; absolute simulator time is arbitrary
	always @(negedge clk) if (!rst) begin
		cycles = cycles + 1;
		if (cycles == 26600001 && bus.base.ticks != 50)
			$fatal(1, "Native clock must produce exactly 50 ticks per 26.6M clocks");
		if (cycles % 5000000 == 0) begin
			$display("\nRT11 progress: clocks=%0d PC=%06o IR=%06o uPC=%04h SD reads=%0d writes=%0d TX=%0d RX=%0d/%0d RCSR=%06o stage=%0d",
				cycles, context_words[7], context_words[9], dut.upc, card.read_count, card.writes, tx_count,
				rx_reads, rx_sent, context_words[20], stage);
			$fflush();
		end
		if (cycles >= max_cycles || dut.cause_reg >= 3)
			$fatal(1, "RT11 stopped: clocks=%0d PC=%06o IR=%06o PSW=%06o uPC=%04h cause=%0d CS1=%06o WC=%06o BA=%06o ER=%06o",
				cycles, context_words[7], context_words[9], context_words[8], dut.upc, dut.cause_reg,
				context_words[40], context_words[41], context_words[42], context_words[46]);
		if (bus.bank_override && req && address < 16'he000 && address >= 512)
			$fatal(1, "DMA escaped the reserved FRAM cache");
	end
	always @(posedge clk) if (!rst && req && ready && !wr && address == 16'hf002)
		rx_reads = rx_reads + 1;
	always @(posedge clk) if (!rst && trace_fd != 0 && dut.context_write_enable && dut.context_write_address == 9)
		$fdisplay(trace_fd, "%0d %06o %06o PS=%06o R0=%06o R1=%06o R2=%06o R3=%06o R4=%06o R5=%06o SP=%06o",
			cycles, context_words[7], dut.context_write_data, context_words[8],
			context_words[0], context_words[1], context_words[2], context_words[3], context_words[4], context_words[5], context_words[6]);

	// Decode actual 115200 8N1 pin traffic, including stop-bit checking.
	initial forever begin
		@(negedge tx);
		if (!rst) begin
			repeat (345) @(negedge clk);
			for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
				tx_byte[bit_index] = tx;
				repeat (230) @(negedge clk);
			end
			if (tx !== 1) $fatal(1, "UART bad stop bit");
			tx_byte = tx_byte & 8'h7f;
			tx_count = tx_count + 1; last_tx = cycles;
			$fwrite(console_fd, "%c", tx_byte & 8'h7f);
			$fflush(console_fd);
			$write("%c", tx_byte & 8'h7f);
			if ((tx_byte & 8'h7f) == 10) begin
				// This RT11 V5.03 fixture ends its startup file with SET SL ON.
				// Its earlier command-echo dot may stay quiet while the file
				// is read from SD; it is NOT yet an interactive KMON prompt.
				if (line == ".SET SL ON") startup_script_done = 1;
				line = "";
			end
			else if (tx_byte != 13) line = {line, tx_byte};
		end
	end
	task wait_prompt;
		begin
			// A quiet, standalone KMON prompt, not a dot in startup command echo.
			while (!startup_script_done || line != "." || tx_count <= previous_prompt_tx || cycles - last_tx < 1000000 || context_words[56][2]) @(negedge clk);
			previous_prompt_tx = tx_count;
			stage = stage + 1;
		end
	endtask
	task send_command(input string command_line);
		integer c, b;
		reg [7:0] value;
		begin
			$display("\nTerminal input: %s", command_line);
			$fflush();
			for (c = 0; c < command_line.len(); c = c + 1) begin
				value = command_line[c];
				@(posedge clk); rx = 0;
				repeat (230) @(posedge clk);
				for (b = 0; b < 8; b = b + 1) begin
					rx = value[b]; repeat (230) @(posedge clk);
				end
				rx = 1; repeat (230) @(posedge clk);
				rx_sent = rx_sent + 1;
				// Pace a human terminal: never overflow either one-byte RX buffer.
				// These are passive observations; no guest/device state is injected.
				repeat (1000) @(posedge clk);
				while (bus.base.uart_rx_ready || context_words[20][7]) @(posedge clk);
				repeat (500000) @(posedge clk);
			end
		end
	endtask
	initial begin
		if ($value$plusargs("MAX_CYCLES=%d", max_cycles)) begin end
		if ($value$plusargs("CONSOLE=%s", console_path)) begin end
		console_fd = $fopen(console_path, "w");
		if (console_fd == 0) $fatal(1, "Cannot open console log");
		if ($value$plusargs("TRACE=%s", trace_path)) trace_fd = $fopen(trace_path, "w");
		#1;
		if (card.image_fd == 0) $fatal(1, "RT11 test requires +SD_IMAGE=raw_disk_image");
		// No guest bootstrap, disk sectors or registers are deposited here.
		repeat (4) @(negedge clk); rst = 0;
		if ($test$plusargs("BOOTSTRAP_ONLY")) begin
			// Real SPI reads filled empty FRAM and entered RT-11's bootstrap.
			wait (context_words[7] == 16'o604);
			if (card.read_count != 2 || card.writes != 0 || bus.bank_override)
				$fatal(1, "Bootstrap did not complete exactly two SD reads");
			for (bootstrap_sector = 0; bootstrap_sector < 2; bootstrap_sector = bootstrap_sector + 1) begin
				card.load_sector(bootstrap_sector);
				for (bootstrap_byte = 0; bootstrap_byte < 512; bootstrap_byte = bootstrap_byte + 1)
					if (fram.memory[bootstrap_sector*512+bootstrap_byte] !== card.image_sector[bootstrap_byte])
						$fatal(1, "Bootstrap disk/FRAM mismatch");
			end
			$display("PASS: RT11 bootstrap, two SPI sectors match FRAM, PC=000604 (%0d clocks)", cycles);
			$finish;
		end
		wait_prompt();
		send_command("SHOW CONFIGURATION\015");
		wait_prompt();
		send_command("DIRECTORY SY:RT11FB.SYS\015");
		wait_prompt();
		$display("\nRT11 simulation complete: %0d clocks, %0d reads, %0d writes, %0d dirty sectors",
			cycles, card.read_count, card.writes, card.dirty_count);
		$fclose(console_fd);
		if (trace_fd != 0) $fclose(trace_fd);
		$finish;
	end
endmodule

`timescale 1ns/1ps

// Execute assembled guest programs against the real native bus/UART/FRAM.
// Only the elapsed-time source is advanced explicitly for deterministic tests;
// no guest CSR, guest interrupt, or guest register is manufactured by this TB.
module tb_j11_peripherals;
	reg clk = 0, rst = 1;
	wire req, wr, byte_access, bank, ready, error, guest_reset, irq;
	wire [2:0] level;
	wire [7:0] vector;
	wire [15:0] address, wdata, rdata;
	wire tx, cs, sck, mosi, miso;
	reg [15:0] waiting_pc;
	integer i, native_reads = 0, previous_reads, tx_count = 0;
	reg [7:0] tx_byte;
	reg [7:0] expected_tx [0:3];

	j11_microengine #(.UROM_WORDS(`J11_UROM_WORDS),
		.UCODE_FILE("build/j11_ucode.words")) engine (
		.clk(clk), .rst(rst), .guest_req(req), .guest_write(wr),
		.guest_byte(byte_access), .guest_bank(bank), .guest_address(address),
		.guest_wdata(wdata), .guest_rdata(rdata), .guest_ready(ready),
		.guest_error(error), .guest_reset(guest_reset), .irq(irq),
		.irq_level(level), .irq_vector(vector)
	);
	j11_hc1200_guest_bus #(.FRAM_CLK_DIV(1),
		.TICK_DIVISOR(1000000000)) services (
		.clk(clk), .rst(rst), .guest_reset(guest_reset), .req(req), .write(wr),
		.byte_access(byte_access), .bank(bank), .address(address), .wdata(wdata),
		.rdata(rdata), .ready(ready), .error(error), .busy(),
		.uart_rx(1'b1), .uart_tx(tx), .irq(irq), .irq_level(level), .irq_vector(vector),
		.spi_cs_n(cs), .spi_sck(sck), .spi_mosi(mosi), .spi_miso(miso)
	);
	spi_fram_model fram (.cs_n(cs), .sck(sck), .mosi(mosi), .miso(miso));
	always #5 clk = !clk;
	always @(posedge clk) if (!rst && req && ready) begin
		if (address >= 16'hff60 && address < 16'hff80)
			$fatal(1, "Guest CSR leaked out of microcode: %06o", address);
		if (address == 16'hf000 && !wr) native_reads = native_reads + 1;
	end

	// Check the actual serial pin, not just data submitted to the UART.
	initial forever begin
		@(negedge tx);
		if (!rst) begin
			repeat (345) @(negedge clk); // 1.5 bits at 26.6 MHz / 115200
			for (i = 0; i < 8; i = i + 1) begin
				tx_byte[i] = tx;
				repeat (230) @(negedge clk);
			end
			if (tx !== 1 || tx_count >= 4 || tx_byte !== expected_tx[tx_count])
				$fatal(1, "Serial frame %0d: %02h", tx_count, tx_byte);
			tx_count = tx_count + 1;
		end
	end

	task tick_to(input [15:0] value);
		begin
			@(negedge clk);
			services.ticks = value;
			services.event_pending = 1;
		end
	endtask
	task expect_wait;
		begin
			while (engine.jctx[9] !== 16'd1) @(negedge clk);
			repeat (400) @(negedge clk);
			waiting_pc = engine.jctx[7];
			repeat (400) begin
				@(negedge clk);
				if (engine.jctx[7] != waiting_pc ||
					(req && address == waiting_pc))
					$fatal(1, "WAIT fetched another guest instruction: stage=%0d PC=%06o saved=%06o address=%06o req=%b IR=%06o cause=%0d",
						engine.jctx[5], engine.jctx[7], waiting_pc, address, req,
						engine.jctx[9], engine.cause_reg);
			end
		end
	endtask

	initial begin
		expected_tx[0] = 8'hc1;
		expected_tx[1] = "B";
		expected_tx[2] = "C";
		expected_tx[3] = "Z";
		#1;
		$readmemh("build/guest_peripherals.hex", fram.memory);
		repeat (4) @(negedge clk);
		rst = 0;
		while (engine.state !== engine.ST_FETCH) @(negedge clk);
		while (engine.jctx[5] != 3 && engine.cause_reg != 3) @(negedge clk);
		if (engine.cause_reg == 3) $fatal(1, "Peripheral stage %0d", engine.jctx[0]);
		tick_to(16'hffff);
		while (engine.jctx[5] != 4 && engine.cause_reg != 3) @(negedge clk);
		previous_reads = native_reads;
		while (engine.jctx[5] != 5 && engine.cause_reg != 3) @(negedge clk);
		if (native_reads != previous_reads)
			$fatal(1, "Idle UART was polled without a native event");
		expect_wait();
		tick_to(0); // 16-bit time sequence wrap
		while (engine.jctx[5] != 6 && engine.cause_reg != 3) @(negedge clk);
		expect_wait();
		tick_to(1);
		while (engine.cause_reg != 3) @(negedge clk);
		if (engine.jctx[0] !== 16'o012345 || tx_count != 4 || services.ticks != 1)
			$fatal(1, "Peripheral result r0=%06o PC=%06o IR=%06o stage=%0d TX=%0d",
				engine.jctx[0], engine.jctx[7], engine.jctx[9], engine.jctx[5], tx_count);

		rst = 1;
		repeat (4) @(negedge clk);
		$readmemh("build/guest_peripherals_wait_masked.hex", fram.memory);
		rst = 0;
		while (engine.state !== engine.ST_FETCH) @(negedge clk);
		expect_wait();
		tick_to(1);
		repeat (2000) @(negedge clk);
		if (engine.jctx[0] !== 1 || engine.jctx[7] !== waiting_pc ||
			engine.jctx[23] !== 16'hc0 || engine.cause_reg == 3)
			$fatal(1, "Masked WAIT accepted BR6 or lost the tick");
		$display("PASS: microcoded DL11/LTC, ODT polling, serial bytes, IRQ priorities/latches, WAIT, RESET, time wrap, private/odd I/O");
		$finish;
	end
	initial begin
		#20000000;
		$fatal(1, "Peripheral timeout PC=%06o IR=%06o uPC=%04h stage=%0d cause=%0d RCSR=%04h XCSR=%04h LTC=%04h",
			engine.jctx[7], engine.jctx[9], engine.upc, engine.jctx[5],
			engine.cause_reg, engine.jctx[20], engine.jctx[22], engine.jctx[23]);
	end
endmodule

`include "include/j11_test_target.vh"
`timescale 1ns/1ps

module tb_j11_execute;
	reg clk;
	reg rst;
	reg irq;
	reg [2:0] irq_level;
	reg [7:0] irq_vector;
	wire guest_req;
	wire guest_write;
	wire guest_byte;
	wire guest_bank;
	wire [15:0] guest_address;
	wire [15:0] guest_wdata;
	wire [15:0] guest_rdata;
	wire guest_ready;
	wire guest_error;
	wire spi_cs_n;
	wire spi_sck;
	wire spi_mosi;
	wire spi_miso;
	wire [15:0] debug_upc;
	wire [15:0] debug_guest_r0;
	wire [15:0] debug_guest_pc;
	wire [15:0] debug_guest_psw;
	wire [15:0] debug_guest_ir;
	wire [15:0] debug_cause;
	wire [15:0] debug_pending_irq;
	wire guest_reset;
	integer guest_reset_count;
	integer test_number = 0;
	time test_started_at = 0;

	`J11_ENGINE_MODULE #(
		.UROM_WORDS(`J11_UROM_WORDS),
		.UCODE_FILE(`J11_UCODE_FILE)
	) dut (
		.clk(clk),
		.rst(rst),
		.guest_req(guest_req),
		.guest_write(guest_write),
		.guest_byte(guest_byte),
		.guest_bank(guest_bank),
		.guest_address(guest_address),
		.guest_wdata(guest_wdata),
		.guest_rdata(guest_rdata),
		.guest_ready(guest_ready),
		.guest_error(guest_error),
		.irq(irq),
		.irq_level(irq_level),
		.irq_vector(irq_vector),
		.guest_reset(guest_reset),
		.debug_upc(debug_upc),
		.debug_guest_r0(debug_guest_r0),
		.debug_guest_pc(debug_guest_pc),
		.debug_guest_psw(debug_guest_psw),
		.debug_guest_ir(debug_guest_ir),
		.debug_cause(debug_cause),
		.debug_pending_irq(debug_pending_irq)
	);

	spi_fram_guest_ram #(
		.CLK_DIV(1)
	) guest_ram (
		.clk(clk),
		.rst(rst),
		.req(guest_req),
		.write(guest_write),
		.byte_access(guest_byte),
		.bank(guest_bank),
		.address(guest_address),
		.wdata(guest_wdata),
		.rdata(guest_rdata),
		.ready(guest_ready),
		.error(guest_error),
		.busy(),
		.spi_cs_n(spi_cs_n),
		.spi_sck(spi_sck),
		.spi_mosi(spi_mosi),
		.spi_miso(spi_miso)
	);

	spi_fram_model fram (
		.cs_n(spi_cs_n),
		.sck(spi_sck),
		.mosi(spi_mosi),
		.miso(spi_miso)
	);

	`define J11_CONTEXT_ENGINE dut
	`include "include/j11_context_probe.vh"
	always #5 clk = !clk;
	always @(posedge clk) begin
		if (guest_reset) begin
			guest_reset_count = guest_reset_count + 1;
		end
	end

	task reset_engine;
		begin
			test_number = test_number + 1;
			test_started_at = $time;
			if ($test$plusargs("TRACE_TESTS"))
				$display("J-11 execute case %0d at %0t", test_number, $time);
			rst = 1;
			repeat (4) @(negedge clk);
			rst = 0;
		end
	endtask

	task expect_fram_word;
		input [16:0] address;
		input [15:0] expected;
		reg [15:0] actual;
		begin
			actual = {fram.memory[address + 1'b1], fram.memory[address]};
			if (actual !== expected) begin
				$display("FAIL: J-11 MOV EA memory[%06o]=%06o expected=%06o",
					address, actual, expected);
				$finish_and_return(1);
			end
		end
	endtask

	task expect_fram_byte;
		input [16:0] address;
		input [7:0] expected;
		begin
			if (fram.memory[address] !== expected) begin
				$display("FAIL: J-11 MOVB EA memory[%06o]=%03o expected=%03o",
					address, fram.memory[address], expected);
				$finish_and_return(1);
			end
		end
	endtask

	initial begin
		clk = 0;
		rst = 1;
		irq = 0;
		irq_level = 0;
		irq_vector = 0;
		guest_reset_count = 0;

		#1;
		$readmemh("build/guest_basic.hex", fram.memory);
		reset_engine();

		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_pc !== 16'h0008 || debug_guest_ir !== 16'h0000) begin
			$display("FAIL: J-11 NOP/BR/HALT pc=%04x ir=%04x cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_cause);
			$finish_and_return(1);
		end

		/* A reserved opcode must enter vector 010 and build a trap frame. */
		$readmemh("build/guest_reserved.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_pc !== 16'o000010 || debug_guest_ir !== 16'h0000 ||
				debug_guest_r0 !== 16'o012345) begin
			$display("FAIL: J-11 reserved vector pc=%06o ir=%06o r0=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0, debug_cause);
			$finish_and_return(1);
		end
		expect_fram_word(17'o001774, 16'o000006);
		expect_fram_word(17'o001776, 16'o000000);

		$readmemh("build/guest_bus_error.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o065432 || debug_guest_ir !== 16'h0000) begin
			$display("FAIL: J-11 bus-error vector pc=%06o ir=%06o r0=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0, debug_cause);
			$finish_and_return(1);
		end
		expect_fram_word(17'o001774, 16'o000020);
		expect_fram_word(17'o001776, 16'o000000);

		$readmemh("build/guest_interrupt.hex", fram.memory);
		reset_engine();
		while (debug_guest_pc != 16'o000004) @(negedge clk);
		irq_level = 3'd4;
		irq_vector = 8'o060;
		irq = 1;
		repeat (2) @(negedge clk);
		irq = 0;
		while (debug_guest_r0 != 16'o012345) @(negedge clk);
		while (debug_guest_pc != 16'o000004 || debug_pending_irq != 0)
			@(negedge clk);
		if (debug_cause !== 0) begin
			$display("FAIL: J-11 IRQ/RTI pc=%06o r0=%06o cause=%04x pending=%04x",
				debug_guest_pc, debug_guest_r0, debug_cause, debug_pending_irq);
			$finish_and_return(1);
		end
		expect_fram_word(17'o001774, 16'o000004);
		expect_fram_word(17'o001776, 16'o000000);

		$readmemh("build/guest_irq_priority.hex", fram.memory);
		reset_engine();
		while (context_words[1] != 16'o000001) @(negedge clk);
		irq_level = 3'd4;
		irq_vector = 8'o060;
		irq = 1;
		repeat (2) @(negedge clk);
		irq = 0;
		repeat (20) @(negedge clk);
		if (debug_guest_r0 !== 0 || debug_guest_psw[7:5] !== 3'd4 ||
				debug_pending_irq[15] !== 1'b1 ||
				debug_pending_irq[10:8] !== 3'd4) begin
			$display("FAIL: J-11 IRQ priority mask r0=%06o psw=%06o pending=%06o",
				debug_guest_r0, debug_guest_psw, debug_pending_irq);
			$finish_and_return(1);
		end
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345 || debug_pending_irq !== 0) begin
			$display("FAIL: J-11 deferred IRQ r0=%06o psw=%06o pending=%06o cause=%04x",
				debug_guest_r0, debug_guest_psw, debug_pending_irq, debug_cause);
			$finish_and_return(1);
		end

		/* A BR5 request must preempt the same priority-4 BPT handler. */
		$readmemh("build/guest_irq_priority.hex", fram.memory);
		reset_engine();
		while (context_words[1] != 16'o000001) @(negedge clk);
		irq_level = 3'd5;
		irq_vector = 8'o060;
		irq = 1;
		repeat (2) @(negedge clk);
		irq = 0;
		while (debug_guest_r0 != 16'o012345) @(negedge clk);
		if (context_words[1] !== 16'o000001 || debug_pending_irq !== 0) begin
			$display("FAIL: J-11 higher-priority IRQ r0=%06o r1=%06o psw=%06o pending=%06o",
				debug_guest_r0, context_words[1], debug_guest_psw,
				debug_pending_irq);
			$finish_and_return(1);
		end
		while (debug_cause != 16'h0003) @(negedge clk);

		$readmemh("build/guest_branches.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_ir !== 16'h0000 || debug_guest_psw[3:0] !== 4'b0001) begin
			$display("FAIL: J-11 condition branches pc=%04x ir=%04x psw=%04x cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end

		$readmemh("build/guest_mov_register.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'h0004 || debug_guest_psw[3:0] !== 4'b0001) begin
			$display("FAIL: J-11 MOV PC,R0 r0=%04x psw=%04x cause=%04x",
				debug_guest_r0, debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end

		$readmemh("build/guest_mov_zero.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'h0000 || debug_guest_psw[3:0] !== 4'b0101) begin
			$display("FAIL: J-11 MOV zero flags r0=%04x psw=%04x cause=%04x",
				debug_guest_r0, debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end

		$readmemh("build/guest_mov_immediate.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o100000 || debug_guest_psw[3:0] !== 4'b1001) begin
			$display("FAIL: J-11 MOV immediate r0=%04x psw=%04x cause=%04x",
				debug_guest_r0, debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end

		$readmemh("build/guest_mov_deferred.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345 || debug_guest_psw[3:0] !== 4'b0001 ||
				fram.memory[17'o002000] !== 8'he5 ||
				fram.memory[17'o002001] !== 8'h14) begin
			$display("FAIL: J-11 MOV deferred r0=%04x psw=%04x mem=%02x%02x",
				debug_guest_r0, debug_guest_psw,
				fram.memory[17'o002001], fram.memory[17'o002000]);
			$finish_and_return(1);
		end

		$readmemh("build/guest_mov_modes.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o100000 || debug_guest_psw[3:0] !== 4'b1001) begin
			$display("FAIL: J-11 MOV EA final state r0=%06o psw=%06o cause=%04x",
				debug_guest_r0, debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end

		expect_fram_word(17'o001000, 16'o011111);
		expect_fram_word(17'o001002, 16'o001202);
		expect_fram_word(17'o001004, 16'o022222);
		expect_fram_word(17'o001006, 16'o001204);
		expect_fram_word(17'o001010, 16'o033333);
		expect_fram_word(17'o001012, 16'o001206);
		expect_fram_word(17'o001014, 16'o044444);
		expect_fram_word(17'o001016, 16'o001210);
		expect_fram_word(17'o001020, 16'o055555);
		expect_fram_word(17'o001022, 16'o066666);
		expect_fram_word(17'o001024, 16'o077777);
		expect_fram_word(17'o001026, 16'o012345);
		expect_fram_word(17'o001030, 16'o076543);
		expect_fram_word(17'o001032, 16'o010101);
		expect_fram_word(17'o001034, 16'o020202);
		expect_fram_word(17'o001036, 16'o001036);
		expect_fram_word(17'o001040, 16'o030303);
		expect_fram_word(17'o001042, 16'o001234);
		expect_fram_word(17'o001044, 16'o040404);
		expect_fram_word(17'o001046, 16'o001044);
		expect_fram_word(17'o001050, 16'o050505);
		expect_fram_word(17'o001052, 16'o001234);
		expect_fram_word(17'o001054, 16'o060606);
		expect_fram_word(17'o001056, 16'o070707);
		expect_fram_word(17'o001060, 16'o011011);
		expect_fram_word(17'o001062, 16'o022022);
		expect_fram_word(17'o001064, 16'o033033);

		$readmemh("build/guest_movb_modes.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o177600 || debug_guest_psw[3:0] !== 4'b1001) begin
			$display("FAIL: J-11 MOVB final state r0=%06o psw=%06o cause=%04x",
				debug_guest_r0, debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end

		expect_fram_word(17'o001000, 16'o177745);
		expect_fram_word(17'o001002, 16'o177601);
		expect_fram_word(17'o001004, 16'o000002);
		expect_fram_word(17'o001006, 16'o001203);
		expect_fram_word(17'o001010, 16'o177603);
		expect_fram_word(17'o001012, 16'o001206);
		expect_fram_word(17'o001014, 16'o000004);
		expect_fram_word(17'o001016, 16'o001210);
		expect_fram_word(17'o001020, 16'o177605);
		expect_fram_word(17'o001022, 16'o001212);
		expect_fram_word(17'o001024, 16'o000006);
		expect_fram_word(17'o001026, 16'o001214);
		expect_fram_word(17'o001030, 16'o177607);
		expect_fram_word(17'o001032, 16'o001216);
		expect_fram_word(17'o001034, 16'o000010);
		expect_fram_word(17'o001036, 16'o177611);
		expect_fram_word(17'o001040, 16'o000012);
		expect_fram_word(17'o001042, 16'o177613);
		expect_fram_word(17'o001044, 16'o000014);
		expect_fram_word(17'o001046, 16'o001102);
		expect_fram_word(17'o001050, 16'o001104);
		expect_fram_word(17'o001052, 16'o001242);
		expect_fram_word(17'o001054, 16'o001104);
		expect_fram_word(17'o001056, 16'o001105);
		expect_fram_word(17'o001060, 16'o001242);

		expect_fram_byte(17'o001100, 8'o021);
		expect_fram_byte(17'o001101, 8'o022);
		expect_fram_byte(17'o001102, 8'o023);
		expect_fram_byte(17'o001103, 8'o024);
		expect_fram_byte(17'o001104, 8'o025);
		expect_fram_byte(17'o001105, 8'o026);
		expect_fram_byte(17'o001106, 8'o027);
		expect_fram_byte(17'o001107, 8'o030);
		expect_fram_byte(17'o001110, 8'o031);
		expect_fram_byte(17'o001111, 8'o032);
		expect_fram_byte(17'o001112, 8'o033);
		expect_fram_byte(17'o001113, 8'o034);

		$readmemh("build/guest_clear_test.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_psw[3:0] !== 4'b1000) begin
			$display("FAIL: J-11 CLR/TST final state psw=%06o cause=%04x",
				debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end
		expect_fram_word(17'o001000, 16'o177400);
		expect_fram_word(17'o001002, 16'o001201);
		expect_fram_word(17'o001004, 16'o000000);
		expect_fram_word(17'o001006, 16'o000345);

		$readmemh("build/guest_double_ops.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o100000 || debug_guest_psw[3:0] !== 4'b1010) begin
			$display("FAIL: J-11 double ops r0=%06o psw=%06o cause=%04x",
				debug_guest_r0, debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end
		expect_fram_word(17'o001000, 16'o000000);
		expect_fram_word(17'o001002, 16'o001202);
		expect_fram_word(17'o001004, 16'o001204);
		expect_fram_word(17'o001200, 16'o012346);
		expect_fram_word(17'o001202, 16'o007653);

		$readmemh("build/guest_ea_timing.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345) begin
			$display("FAIL: J-11 register-source EA timing pc=%06o ir=%06o r0=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0, debug_cause);
			$finish_and_return(1);
		end
		expect_fram_word(17'o002000, 16'o002002);
		expect_fram_word(17'o002200, 16'o002102);
		expect_fram_word(17'o002300, 16'o002300);
		expect_fram_word(17'o002500, 16'o002400);
		expect_fram_byte(17'o003000, 8'o001);
		expect_fram_word(17'o003200, 16'o003202);
		expect_fram_byte(17'o003400, 8'o001);
		expect_fram_word(17'o001000, 16'o000776);
		expect_fram_byte(17'o003600, 8'o001);
		expect_fram_word(17'o004000, 16'o004003);

		$readmemh("build/guest_bic_bis.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345) begin
			$display("FAIL: J-11 BIC/BIS pc=%06o ir=%06o r0=%06o psw=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end
		expect_fram_word(17'o001000, 16'o012205);
		expect_fram_word(17'o001002, 16'o001007);
		expect_fram_word(17'o001004, 16'o001010);
		expect_fram_byte(17'o001007, 8'o217);
		expect_fram_word(17'o001010, 16'o052045);

		$readmemh("build/guest_control_flow.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345) begin
			$display("FAIL: J-11 JMP/JSR/RTS pc=%06o ir=%06o r0=%06o psw=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end

		$readmemh("build/guest_control_traps.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345 || context_words[5] !== 16'o065432) begin
			$display("FAIL: J-11 JMP/JSR mode-0 traps pc=%06o ir=%06o r0=%06o r5=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				context_words[5], debug_cause);
			$finish_and_return(1);
		end

		$readmemh("build/guest_sob.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345 || context_words[1] !== 0 ||
				context_words[2] !== 16'o000003) begin
			$display("FAIL: J-11 SOB pc=%06o ir=%06o r0=%06o r1=%06o r2=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				context_words[1], context_words[2], debug_cause);
			$finish_and_return(1);
		end

		$readmemh("build/guest_software_traps.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345 || context_words[6] !== 16'o002000) begin
			$display("FAIL: J-11 software traps pc=%06o ir=%06o r0=%06o sp=%06o psw=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				context_words[6], debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end

		$readmemh("build/guest_com.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345 || context_words[1] !== 16'o012000 ||
				context_words[2] !== 0) begin
			$display("FAIL: J-11 COM/B pc=%06o ir=%06o r0=%06o r1=%06o r2=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				context_words[1], context_words[2], debug_cause);
			$finish_and_return(1);
		end
		expect_fram_byte(17'o001001, 8'o125);
		expect_fram_byte(17'o001003, 8'o170);
		expect_fram_word(17'o001004, 16'o165432);

		$readmemh("build/guest_inc_dec.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345) begin
			$display("FAIL: J-11 INC/DEC pc=%06o ir=%06o r0=%06o r1=%06o r2=%06o psw=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				context_words[1], context_words[2], debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end
		expect_fram_word(17'o001000, 16'o000002);
		expect_fram_byte(17'o001002, 8'o000);
		expect_fram_byte(17'o001003, 8'o125);
		expect_fram_word(17'o001006, 16'o000004);
		expect_fram_word(17'o001010, 16'o000004);
		expect_fram_word(17'o001014, 16'o000005);
		expect_fram_word(17'o001016, 16'o000007);
		expect_fram_word(17'o001022, 16'o000007);
		expect_fram_word(17'o001024, 16'o000011);
		expect_fram_word(17'o001030, 16'o000011);

		$readmemh("build/guest_neg_adc_sbc.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345) begin
			$display("FAIL: J-11 NEG/ADC/SBC pc=%06o ir=%06o r0=%06o r1=%06o r2=%06o psw=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				context_words[1], context_words[2], debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end
		expect_fram_word(17'o001000, 16'o177777);
		expect_fram_byte(17'o001002, 8'o000);
		expect_fram_byte(17'o001003, 8'o125);
		expect_fram_word(17'o001004, 16'o177777);

		$readmemh("build/guest_shift_rotate.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345) begin
			$display("FAIL: J-11 shift/rotate pc=%06o ir=%06o r0=%06o r1=%06o r2=%06o psw=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				context_words[1], context_words[2], debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end
		expect_fram_word(17'o003000, 16'o000000);
		expect_fram_byte(17'o003002, 8'o001);
		expect_fram_byte(17'o003003, 8'o125);
		expect_fram_word(17'o003004, 16'o000000);
		expect_fram_word(17'o003006, 16'o000000);

		$readmemh("build/guest_swab.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345) begin
			$display("FAIL: J-11 SWAB pc=%06o ir=%06o r0=%06o r1=%06o r2=%06o psw=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				context_words[1], context_words[2], debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end
		expect_fram_word(17'o001000, 16'o162424);

		$readmemh("build/guest_sxt.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345 || context_words[4] !== 0) begin
			$display("FAIL: J-11 SXT pc=%06o ir=%06o r0=%06o r4=%06o psw=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				context_words[4], debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end
		expect_fram_word(17'o001000, 16'o177777);

		$readmemh("build/guest_xor.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345) begin
			$display("FAIL: J-11 XOR pc=%06o ir=%06o r0=%06o psw=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end
		expect_fram_word(17'o001000, 16'o177777);

		$readmemh("build/guest_psw.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345 ||
				(debug_guest_psw & 16'o000420) !== 16'o000420) begin
			$display("FAIL: J-11 MFPS/MTPS pc=%06o ir=%06o r0=%06o r1=%06o r2=%06o r3=%06o r4=%06o r5=%06o psw=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				context_words[1], context_words[2], context_words[3], context_words[4],
				context_words[5], debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end
		expect_fram_byte(17'o001000, 8'o221);
		expect_fram_byte(17'o001001, 8'o125);

		$readmemh("build/guest_system.hex", fram.memory);
		reset_engine();
		while (debug_guest_r0 != 16'o000001) @(negedge clk);
		// Synchronize on WAIT itself, not a guessed instruction latency: the
		// memory dispatcher may otherwise deliver the IRQ before WAIT executes.
		while (debug_guest_ir != 16'o000001) @(negedge clk);
		repeat (100) @(negedge clk);
		if (debug_guest_r0 !== 16'o000001 || debug_cause !== 0) begin
			$display("FAIL: J-11 WAIT did not hold pc=%06o ir=%06o r0=%06o psw=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end
		irq_level = 3'd4;
		irq_vector = 8'o060;
		irq = 1;
		repeat (2) @(negedge clk);
		irq = 0;
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345 || context_words[1] !== 16'o000001) begin
			$display("FAIL: J-11 MFPT/SPL/WAIT pc=%06o ir=%06o r0=%06o r1=%06o psw=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				context_words[1], debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end

		$readmemh("build/guest_reset_rtt.hex", fram.memory);
		guest_reset_count = 0;
		reset_engine();
		irq_level = 3'd0;
		irq_vector = 8'o060;
		irq = 1;
		repeat (2) @(negedge clk);
		irq = 0;
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345 || context_words[1] !== 16'o000001 ||
				guest_reset_count !== 1 || debug_pending_irq !== 0) begin
			$display("FAIL: J-11 RESET/RTT pc=%06o ir=%06o r0=%06o r1=%06o psw=%06o reset_count=%0d pending=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				context_words[1], debug_guest_psw, guest_reset_count,
				debug_pending_irq, debug_cause);
			$finish_and_return(1);
		end

		$readmemh("build/guest_mul.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345) begin
			$display("FAIL: J-11 MUL pc=%06o ir=%06o r0=%06o r1=%06o psw=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				context_words[1], debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end

		$readmemh("build/guest_ash.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345) begin
			$display("FAIL: J-11 ASH pc=%06o ir=%06o r0=%06o r1=%06o psw=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				context_words[1], debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end

		$readmemh("build/guest_ashc.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345) begin
			$display("FAIL: J-11 ASHC pc=%06o ir=%06o r0=%06o r1=%06o psw=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				context_words[1], debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end

		$readmemh("build/guest_div.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345) begin
			$display("FAIL: J-11 DIV pc=%06o ir=%06o r0=%06o r1=%06o r4=%06o r5=%06o psw=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				context_words[1], context_words[4], context_words[5], debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end

		$readmemh("build/guest_mark_lock.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345) begin
			$display("FAIL: J-11 MARK/TSTSET/WRTLCK pc=%06o ir=%06o r0=%06o r1=%06o r2=%06o r5=%06o lock=%06o write=%06o traps=%06o psw=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				context_words[1], context_words[2], context_words[5],
				{fram.memory[17'o001001], fram.memory[17'o001000]},
				{fram.memory[17'o001003], fram.memory[17'o001002]},
				{fram.memory[17'o001005], fram.memory[17'o001004]},
				debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end

		$readmemh("build/guest_mark_edges.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345) begin
			$display("FAIL: J-11 MARK NN boundaries pc=%06o ir=%06o r0=%06o r5=%06o sp=%06o psw=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				context_words[5], context_words[6], debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end

		$readmemh("build/guest_lock_edges.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345) begin
			$display("FAIL: J-11 lock flag boundaries pc=%06o ir=%06o r0=%06o r3=%06o psw=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				context_words[3], debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end

		$readmemh("build/guest_trace_return.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345 || context_words[1] !== 2 || context_words[2] !== 2) begin
			$display("FAIL: J-11 RTI/RTT trace boundaries pc=%06o ir=%06o r0=%06o r1=%06o r2=%06o sp=%06o psw=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				context_words[1], context_words[2], context_words[6], debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end

		$readmemh("build/guest_previous_space.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345) begin
			$display("FAIL: J-11 MFPI/MFPD/MTPI/MTPD pc=%06o ir=%06o r0=%06o r2=%06o r3=%06o sp=%06o psw=%06o cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				context_words[2], context_words[3], context_words[6], debug_guest_psw, debug_cause);
			$finish_and_return(1);
		end

		$readmemh("build/guest_privileged.hex", fram.memory);
		guest_reset_count = 0;
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345 || guest_reset_count !== 1) begin
			$display("FAIL: J-11 privileged PSW modes pc=%06o ir=%06o r0=%06o r1=%06o r2=%06o r3=%06o r4=%06o r5=%06o sp=%06o psw=%06o reset_count=%0d cause=%04x",
				debug_guest_pc, debug_guest_ir, debug_guest_r0,
				context_words[1], context_words[2], context_words[3], context_words[4],
				context_words[5], context_words[6], debug_guest_psw,
				guest_reset_count, debug_cause);
			$finish_and_return(1);
		end

		$readmemh("build/guest_sp_banks.hex", fram.memory);
		reset_engine();
		while (debug_cause != 16'h0003) @(negedge clk);
		if (debug_guest_r0 !== 16'o012345 || context_words[6] !== 16'o010000 ||
				context_words[17] !== 16'o012010 || context_words[19] !== 16'o014010) begin
			$display("FAIL: J-11 SP banks pc=%06o r0=%06o sp=%06o ssp=%06o usp=%06o",
				debug_guest_pc, debug_guest_r0, context_words[6], context_words[17], context_words[19]);
			$finish_and_return(1);
		end

		$display("PASS: microasm11 guests execute traps, banked SP, privileged PSW modes, priority IRQ/RTI, RESET/RTT/TRACE, WAIT, MFPT, SPL, JMP/JSR/RTS, MARK, SOB, software traps, branches, CC, MOV/B, CMP/B, BIT/B, BIC/B, BIS/B, XOR, MUL, DIV, ASH, ASHC, TSTSET, WRTLCK, MFPI/MFPD/MTPI/MTPD, ADD, SUB, CLR/B, COM/B, INC/B, DEC/B, NEG/B, ADC/B, SBC/B, ROR/B, ROL/B, ASR/B, ASL/B, SWAB, SXT, MFPS, MTPS, TST/B and DCJ11 EA timing");
		$finish_and_return(0);
	end

	initial begin
		// Bound each program separately; a growing suite must not consume the
		// final program's timeout merely by passing all preceding programs.
		forever begin
			#100000;
			if ($time - test_started_at > 10000000) begin
				$display("FAIL: J-11 execute timeout test=%0d pc=%04x ir=%04x cause=%04x upc=%04x",
					test_number, debug_guest_pc, debug_guest_ir, debug_cause, debug_upc);
				$finish_and_return(1);
			end
		end
	end

endmodule

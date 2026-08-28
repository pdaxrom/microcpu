`timescale 1ns/1ps

// EXPERIMENTAL: SD boot top; sd.lpf records the supplied, unverified SD pinout.
module ucode_sd_microcomp #(
	parameter integer UROM_WORDS = 3584,
	parameter UCODE_FILE = "j11_sd.mem",
	parameter integer FRAM_CLK_DIV = 2,
	parameter integer TICK_DIVISOR = 532000, // 26.6 MHz / 50 Hz
	parameter integer SD_SLOW_DIV = 68,
	parameter integer SD_FAST_DIV = 2
) (
	output wire       sd_cs_n, sd_sck, sd_mosi,
	input wire        sd_miso,
	input  wire       res,
	input  wire       rx,
	output wire       tx,

	output wire       gpio_mosi,
	input  wire       gpio_miso,
	output wire       gpio_msck,
	output wire       gpio_mcs,

	output wire       gpio_din,
	output wire       gpio_ce,
	output wire       gpio_clk,
	output wire       gpio_rs,
	output wire       gpio_blank,
	output wire       gpio_reg_latch,
	input  wire [3:0] gpio_key_row
);

	wire clk;
	// GSR initializes this generic reset synchronizer at FPGA configuration.
	// Start even if the active-low board reset button is never pressed.
	reg [1:0] reset_sync = 2'b11;
	wire reset = reset_sync[0];

	wire        guest_req;
	wire        guest_write;
	wire        guest_byte;
	wire        guest_bank;
	wire [15:0] guest_address;
	wire [15:0] guest_wdata;
	wire [15:0] guest_rdata;
	wire        guest_ready;
	wire        guest_error;
	wire        guest_busy;
	wire        guest_reset;
	wire        guest_irq;
	wire [2:0]  guest_irq_level;
	wire [7:0]  guest_irq_vector;

	wire [15:0] debug_upc;
	wire [15:0] debug_guest_r0;
	wire [15:0] debug_guest_pc;
	wire [15:0] debug_guest_psw;
	wire [15:0] debug_guest_ir;
	wire [15:0] debug_cause;
	wire [15:0] debug_pending_irq;

	OSCH #(
		.NOM_FREQ("26.60")
	) internal_oscillator (
		.STDBY(1'b0),
		.OSC(clk)
	);

	always @(posedge clk or negedge res) begin
		if (!res) reset_sync <= 2'b11;
		else reset_sync <= {1'b0, reset_sync[1]};
	end

	/*
	 * The original board drives the FRAM pins through software GPIO.  In the
	 * J-11 configuration these four package pins belong exclusively to the
	 * hardware guest-memory controller.
	 */
	ucode_sd_guest_bus #(
		.FRAM_CLK_DIV(FRAM_CLK_DIV),
		.TICK_DIVISOR(TICK_DIVISOR), .SD_SLOW_DIV(SD_SLOW_DIV), .SD_FAST_DIV(SD_FAST_DIV)
	) guest_bus (
		.clk(clk),
		.rst(reset),
		.guest_reset(guest_reset),
		.req(guest_req),
		.write(guest_write),
		.byte_access(guest_byte),
		.bank(guest_bank),
		.address(guest_address),
		.wdata(guest_wdata),
		.rdata(guest_rdata),
		.ready(guest_ready),
		.error(guest_error),
		.busy(guest_busy),
		.uart_rx(rx),
		.uart_tx(tx),
		.irq(guest_irq),
		.irq_level(guest_irq_level),
		.irq_vector(guest_irq_vector),
		.spi_cs_n(gpio_mcs),
		.spi_sck(gpio_msck),
		.spi_mosi(gpio_mosi),
		.spi_miso(gpio_miso),
		.sd_cs_n(sd_cs_n), .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_miso(sd_miso)
	);

	ucode_cpu #(
		.UROM_WORDS(UROM_WORDS),
		.UCODE_FILE(UCODE_FILE)
	) engine (
		.clk(clk),
		.rst(reset),
		.guest_req(guest_req),
		.guest_write(guest_write),
		.guest_byte(guest_byte),
		.guest_bank(guest_bank),
		.guest_address(guest_address),
		.guest_wdata(guest_wdata),
		.guest_rdata(guest_rdata),
		.guest_ready(guest_ready),
		.guest_error(guest_error),
		.irq(guest_irq),
		.irq_level(guest_irq_level),
		.irq_vector(guest_irq_vector),
		.guest_reset(guest_reset),
		.debug_upc(debug_upc),
		.debug_guest_r0(debug_guest_r0),
		.debug_guest_pc(debug_guest_pc),
		.debug_guest_psw(debug_guest_psw),
		.debug_guest_ir(debug_guest_ir),
		.debug_cause(debug_cause),
		.debug_pending_irq(debug_pending_irq)
	);

	/* Peripherals not routed into the guest bus yet are left electrically safe. */
	assign gpio_din = 1'b0;
	assign gpio_ce = 1'b1;
	assign gpio_clk = 1'b0;
	assign gpio_rs = 1'b0;
	assign gpio_blank = 1'b1;
	assign gpio_reg_latch = 1'b0;

endmodule

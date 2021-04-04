module demo (
	input			res,
	input			rx,
	output			tx,

	inout	[3:0]	gpio,
	
	output			gpio_mosi,
	input			gpio_miso,
	output			gpio_msck,
	output			gpio_mcs,
	
	output			gpio_din,
	output			gpio_ce,
	output			gpio_clk,
	output			gpio_rs,
	output			gpio_blank,
	output			gpio_reg_latch,
	input	[3:0]	gpio_key_row
);

	wire				CLK;
	reg				RESET;

	wire	[15:0]	ADDR;
	wire	[7:0]	DI;
	wire	[7:0]	DO;
	wire			RW;

	OSCH #(
		.NOM_FREQ("26.60")
	) internal_oscillator_inst (
		.STDBY(1'b0), 
		.OSC(CLK)
	);

	always @(posedge CLK) begin
		if (res) begin
			RESET <= 0;
		end else begin
			RESET <= 1;
		end
	end
	
//	wire DS0 = (ADDR[15:5] == 11'b11100110000); // $E600
//	wire DS1 = (ADDR[15:5] == 11'b11100110001); // $E620
//	wire DS2 = (ADDR[15:5] == 11'b11100110010); // $E640
//	wire DS3 = (ADDR[15:5] == 11'b11100110011); // $E660
//	wire DS4 = (ADDR[15:5] == 11'b11100110100); // $E680
//	wire DS5 = (ADDR[15:5] == 11'b11100110101); // $E6A0
//	wire DS6 = (ADDR[15:5] == 11'b11100110110); // $E6C0
	wire DS7 = (ADDR[15:5] == 11'b11111111111); // $FFE0

	wire UART_CS = DS7 && (ADDR[4:3] == 2'b00); // $FFE0
	wire UART_EN = UART_CS;
	wire [7:0] UART_D;
	
	uart uart1(
		.clk(CLK),
		.reset(RESET),
		.a0(ADDR[0]),
		.din(DO),
		.dout(UART_D),
		.rnw(RW),
		.cs(UART_CS),
		.rxd(rx),
		.txd(tx)
	);

	wire GPIO_CS = DS7 && (ADDR[4:3] == 2'b01); // $FFE8
	wire GPIO_EN = GPIO_CS;
	wire [7:0] GPIO_D;
	
	//wire gpio15;
	
	gpio gpio1(
		.clk(CLK),
		.rst(RESET),
		.AD(ADDR[2:0]),
		.DI(DO),
		.DO(GPIO_D),
		.rw(RW),
		.cs(GPIO_CS),
		.gpio(gpio),
		.gpio_mosi(gpio_mosi),
		.gpio_miso(gpio_miso),
		.gpio_msck(gpio_msck),
		.gpio_mcs(gpio_mcs),
		.gpio_din(gpio_din),
		.gpio_ce(gpio_ce),
		.gpio_clk(gpio_clk),
		.gpio_rs(gpio_rs),
		.gpio_blank(gpio_blank),
		.gpio_reg_latch(gpio_reg_latch),
		.gpio_key_row(gpio_key_row)
	);

	wire TIMER_CS = DS7 && (ADDR[4:3] == 2'b10); // $FFF0
	wire TIMER_EN = TIMER_CS;
	wire [7:0] TIMER_D;
	wire intr_timer;
	timer timer1(
		.clk(CLK),
		.rst(RESET),
		.AD(ADDR[1:0]),
		.DI(DO),
		.DO(TIMER_D),
		.rw(RW),
		.cs(TIMER_CS),
		.intr(intr_timer)
	);

	// zero page
	wire SRAM_CS = (ADDR[15:11] == 5'b00000);
	wire SRAM_EN = SRAM_CS;
	wire [7:0] SRAM_D;
	sram sram0(
		.Clock(CLK),
		.ClockEn(SRAM_CS),
		.Reset(RESET),
		.WE(~RW),
		.Address(ADDR[10:0]),
		.Data(DO),
		.Q(SRAM_D)
	);

	// pages 1,2
	reg [9:0] MEM_pages;
	wire SRAM2_CS = (ADDR[15:11] == MEM_pages[9:5]);
	wire SRAM1_CS = (ADDR[15:11] == MEM_pages[4:0]);
	wire SRAMP_EN = (SRAM2_CS | SRAM1_CS);
	wire [7:0] SRAMP_D;
	srampages srampages(
		.Clock(CLK),
		.ClockEn(SRAMP_EN),
		.Reset(RESET),
		.WE(~RW),
		.Address({SRAM2_CS, ADDR[10:0]}),
		.Data(DO),
		.Q(SRAMP_D)
	);

	wire MEMMAP_CS = DS7 && (ADDR[4:3] == 2'b11); // $FFF8
	wire MEMMAP_EN = MEMMAP_CS;
	wire SRAM1_wr = (SRAM1_CS && ~RW);
	wire SRAM2_wr = (SRAM2_CS && ~RW);
	reg  SRAM1_dirty;
	reg  SRAM2_dirty;
	reg  [4:0] MEM_addr;
	wire [7:0] MEMMAP_D = ADDR[1] ? {MEM_addr[4:0], 3'b000} :
							ADDR[0] ? { MEM_pages[9:5], 2'b00, SRAM2_dirty} :
							{MEM_pages[4:0], 2'b00, SRAM1_dirty};
	
	reg intr_memmap; // = ~(SRAM_EN | SRAMP_EN | DS7);

	always @(posedge CLK) begin
		if (RESET) begin
			MEM_pages <=  10'b00010_00001; // page 1 and page 2
			MEM_addr <= 0;
			intr_memmap <= 0;
		end else if (MEMMAP_CS && ~RW) begin
			if (ADDR[0]) begin
				MEM_pages[9:5] <= DO[7:3];
				SRAM2_dirty <= 0;
			end else begin
				MEM_pages[4:0] <= DO[7:3];
				SRAM1_dirty <= 0;
			end
			intr_memmap <= 0;
		end else if (~(SRAM_EN | SRAMP_EN | DS7)) begin
			intr_memmap <= 1;
			MEM_addr <= ADDR[15:11];
		end
		if (SRAM1_wr) SRAM1_dirty <= 1;
		if (SRAM2_wr) SRAM2_dirty <= 1;
	end

	assign DI = UART_EN ? UART_D :
				GPIO_EN ? GPIO_D :
				TIMER_EN ? TIMER_D :
				MEMMAP_EN ? MEMMAP_D :
				SRAM_EN ? SRAM_D :
				SRAMP_EN ? SRAMP_D :
				0;

	cpu cpu1 (
		.clk(CLK),
		.rst(RESET),
		.read(RW),
		.address(ADDR),
		.dout(DO),
		.din(DI),
		.intr(intr_timer | intr_memmap)
	);

endmodule

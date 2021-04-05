module demo (
	input			res,
	input			rx,
	output			tx,
	inout	[14:0]	gpio
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
		.AD(ADDR[1:0]),
		.DI(DO),
		.DO(GPIO_D),
		.rw(RW),
		.cs(GPIO_CS),
		.gpio(gpio)
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
	wire SRAM2_CS = (ADDR[15:11] == 5'b00010);
	wire SRAM1_CS = (ADDR[15:11] == 5'b00001);
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

	assign DI = UART_EN ? UART_D :
				GPIO_EN ? GPIO_D :
				TIMER_EN ? TIMER_D :
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
		.intr(intr_timer)
	);

endmodule

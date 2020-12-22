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
		.NOM_FREQ("2.08")
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
	wire DS7 = (ADDR[15:5] == 11'b11100110111); // $E6E0

	wire UART_CS = DS7 && (ADDR[4:3] == 2'b00); // $E6E0
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

	wire GPIO_CS = DS7 && (ADDR[4:3] == 2'b01); // $E6E8
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
		.gpio({res, gpio[14:0]})
	);

	wire TIMER_CS = DS7 && (ADDR[4:3] == 2'b10); // $E6F0
	wire TIMER_EN = TIMER_CS;
	wire [7:0] TIMER_D;
	wire intr;
	timer timer1(
		.clk(CLK),
		.rst(RESET),
		.AD(ADDR[1:0]),
		.DI(DO),
		.DO(TIMER_D),
		.rw(RW),
		.cs(TIMER_CS),
		.intr(intr)
	);

	wire MEMMAP_CS = DS7 && (ADDR[4:3] == 2'b11); // $E6F8
	wire MEMMAP_EN = MEMMAP_CS;
	reg [9:0] MEM_pages;
	wire [7:0] MEMMAP_D = {(ADDR[0]) ? MEM_pages[9:5] : MEM_pages[4:0], 3'b000};
	
	always @(posedge CLK) begin
		if (RESET) MEM_pages <=  10'b00010_00001; // page 1 and page 2
		else if (MEMMAP_CS && ~RW) begin
			if (ADDR[0]) MEM_pages[9:5] <= DO[7:3];
			else MEM_pages[4:0] <= DO[7:3];
		end
	end	
	
	// pages 1,2
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

	assign DI = SRAM_EN ? SRAM_D :
				SRAMP_EN ? SRAMP_D :
				UART_EN ? UART_D :
				GPIO_EN ? GPIO_D :
				TIMER_EN ? TIMER_D :
				MEMMAP_EN ? MEMMAP_D :
				8'b11111111;

	cpu cpu1 (
		.clk(CLK),
		.rst(RESET),
		.read(RW),
		.address(ADDR),
		.dout(DO),
		.din(DI),
		.intr(intr)
	);

endmodule

module demo (
	input			res,
	output	[7:0]	seg,
	output	[3:0]	dig
);

	reg				CLK;
	reg				RESET;

	wire	[15:0]	ADDR;
	wire	[7:0]	DI;
	wire	[7:0]	DO;
	wire			RW;

	reg		[1:0]	dig_counter;
//	reg		[7:0]	led_mem[1:0];
	reg		[7:0]	led_mem;
	
	assign	dig = dig_counter == 3 ? 4'b1000 :
				  dig_counter == 2 ? 4'b0100 :
				  dig_counter == 1 ? 4'b0010 :
				  4'b0001;

//	wire	[3:0] hexin;
	
	wire [3:0] hexin = dig_counter == 0 ? ADDR[7:4] :
					dig_counter == 1 ? ADDR[3:0] :
					dig_counter == 2 ? led_mem[7:4] :
					led_mem[3:0];

//	assign hexin = dig_counter == 0 ? ADDR[7:4] :
//					dig_counter == 1 ? ADDR[3:0] :
//					dig_counter == 2 ? DI[7:4] :
//					DI[3:0];

//	assign hexin = dig_counter == 0 ? ADDR[15:12] :
//					dig_counter == 1 ? ADDR[11:8] :
//					dig_counter == 2 ? ADDR[7:4] :
//					ADDR[3:0];


	assign seg[7] = 1;

//	assign seg[7] = ~(dig_counter == 0 ? ADDR[11] :
//					 dig_counter == 1 ? ADDR[10] :
//					 dig_counter == 2 ? ADDR[9] :
//					 ADDR[8]);


	segled segled1(
		.x(hexin),
		.z(seg[6:0])
	);


	wire xCLK;
	reg		[31:0] clk_divider;

	OSCH #(
		.NOM_FREQ("2.08")
	) internal_oscillator_inst (
		.STDBY(1'b0), 
		.OSC(xCLK)
	);

	always @(posedge xCLK) begin
		if (dig_counter == 3) dig_counter <= 0;
		else dig_counter <= dig_counter + 1;				

		if (clk_divider == 1000000) begin
			clk_divider <= 0;
			CLK <= ~CLK;
		end else begin
			clk_divider <= clk_divider + 1;
		end

	end	

	always @(posedge CLK) begin
		if (res) begin
			RESET <= 0;
		end else begin
			RESET <= 1;
		end
	end

	wire SRAM_CS = ADDR[15] ? 0 : 1;
	wire sram_en = SRAM_CS;
	wire [7:0] sramd;
	sram sram1(
		.Clock(CLK),
		.ClockEn(SRAM_CS),
		.Reset(RESET),
		.WE(~RW),
		.Address(ADDR[9:0]),
		.Data(DO),
		.Q(sramd)
	);

	wire LEDS_CS = ADDR[15] ? 1 : 0;
	wire leds_en = LEDS_CS;
	always @(posedge CLK) begin
		if (LEDS_CS && ~RW) begin
			led_mem <= DO;
		end
	end

	assign DI = sram_en ? sramd :
				leds_en ? led_mem :
				8'b11111111;

	cpu cpu1 (
		.clk(CLK),
		.rst(RESET),
		.read(RW),
		.address(ADDR),
		.dout(DO),
		.din(DI)
	);

endmodule

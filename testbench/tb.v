module test_bench;

	wire	[15:0]	ADDR;
	wire	[7:0]	DI;
	wire	[7:0]	DO;
	wire			RW;

	reg				CLK;
	reg				RST;

	wire	[4:0]	d_op;
	wire	[2:0]	d_dest;
	wire	[2:0]	d_arg1;
	wire	[4:0]	d_arg2;

	initial begin
		CLK <= 0;
		RST <= 1;
		#200;
		CLK <= 0;
		RST <= 0;
		#100;
//		CLK <= 1;
//		#25;
//		RST <= 1;
//		#25;
	end

	initial begin
		forever #50 CLK = !CLK;
	end

	initial begin
		$dumpfile("tb.vcd");
		$dumpvars(0, core1);
		$monitor("%t clk=%b rst=%b rw=%b addr=%h di=%h do=%h -- op=%h dst=%h arg1=%h arg2=%h",
			$time, CLK, RST, RW, ADDR, DI, DO, d_op, d_dest, d_arg1, d_arg2);
		
		#12000 $finish;
	end

	cpu core1 (
		.clk(CLK),
		.rst(RST),
		.address(ADDR),
		.din(DO),
		.dout(DI),
		.read(RW),
		.d_op(d_op),
		.d_dest(d_dest),
		.d_arg1(d_arg1),
		.d_arg2(d_arg2)
	);

	sram sram1(
		.ADDR(ADDR[7:0]),
		.DI(DI),
		.DO(DO),
		.RW(RW),
		.CS(1'b0)
	);

endmodule

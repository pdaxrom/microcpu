`timescale 1ns/1ps

module OSCH #(parameter NOM_FREQ = "26.60") (
	input wire STDBY,
	output reg OSC
);
	initial begin
		OSC = 0;
		forever #5 OSC = STDBY ? OSC : !OSC;
	end
endmodule

module sram (
	input wire        Clock,
	input wire        ClockEn,
	input wire        Reset,
	input wire        WE,
	input wire [10:0] Address,
	input wire [7:0]  Data,
	output wire [7:0] Q
);
	reg [7:0] Mem [0:2047];
	reg [1023:0] sram_hex;
	integer i;

	initial begin
		for (i = 0; i < 2048; i = i + 1) begin
			Mem[i] = 8'h00;
		end
		if ($value$plusargs("SRAM_HEX=%s", sram_hex)) begin
			$readmemh(sram_hex, Mem);
		end
	end

	assign Q = ClockEn ? Mem[Address] : 8'h00;

	always @(posedge Clock) begin
		if (!Reset && ClockEn && WE) begin
			Mem[Address] <= Data;
		end
	end
endmodule

module srampages (
	input wire        Clock,
	input wire        ClockEn,
	input wire        Reset,
	input wire        WE,
	input wire [11:0] Address,
	input wire [7:0]  Data,
	output wire [7:0] Q
);
	reg [7:0] Mem [0:4095];
	integer i;

	initial begin
		for (i = 0; i < 4096; i = i + 1) begin
			Mem[i] = 8'h00;
		end
	end

	assign Q = ClockEn ? Mem[Address] : 8'h00;

	always @(posedge Clock) begin
		if (!Reset && ClockEn && WE) begin
			Mem[Address] <= Data;
		end
	end
endmodule

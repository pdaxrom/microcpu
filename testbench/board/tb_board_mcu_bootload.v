`timescale 1ns/1ps

module tb_board_mcu_bootload;
	localparam integer BIT_TIME = 2310;
	localparam integer PAYLOAD_LEN = 14;

	reg res;
	reg rx;
	wire tx;
	wire [14:0] gpio;
	reg [7:0] payload [0:PAYLOAD_LEN - 1];
	reg [1023:0] payload_hex;
	integer i;

	assign gpio = 15'hzzzz;

	demo dut (
		.res(res),
		.rx(rx),
		.tx(tx),
		.gpio(gpio)
	);

	initial begin
		for (i = 0; i < PAYLOAD_LEN; i = i + 1) begin
			payload[i] = 8'h00;
		end
		if (!$value$plusargs("PAYLOAD_HEX=%s", payload_hex)) begin
			$display("FAIL: missing +PAYLOAD_HEX=<hex-file>");
			$finish_and_return(1);
		end
		$readmemh(payload_hex, payload);

		res = 0;
		rx = 1;
		#100;
		res = 1;

		fork
			begin
				expect_banner();

				send_uart(8'h4c); // L
				send_uart(8'h08);
				send_uart(8'h00);
				send_uart(8'h08);
				send_uart(8'h0e);
				for (i = 0; i < PAYLOAD_LEN; i = i + 1) begin
					if (i == PAYLOAD_LEN - 1) begin
						send_uart_final(payload[i]);
					end else begin
						send_uart(payload[i]);
					end
				end
				expect_uart(payload[PAYLOAD_LEN - 1]);
				check_payload();

				expect_banner();

				send_uart(8'h47); // G
				send_uart(8'h08);
				send_uart_final(8'h00);
				expect_uart(8'h52); // R

				$display("PASS: hc1200-mcu UART RX bootload");
				$finish_and_return(0);
			end
			begin
				#12000000;
				$display("FAIL: hc1200-mcu UART RX bootload timeout");
				$finish_and_return(1);
			end
		join
	end

	task send_uart;
		input [7:0] value;
		begin
			send_uart_raw(value);
			repeat (2000) @(posedge dut.CLK);
		end
	endtask

	task send_uart_final;
		input [7:0] value;
		integer bit_index;
		begin
			rx = 1'b1;
			repeat (231) @(posedge dut.CLK);
			drive_uart_bit(1'b0);
			for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
				drive_uart_bit(value[bit_index]);
			end
			rx = 1'b1;
		end
	endtask

	task send_uart_raw;
		input [7:0] value;
		integer bit_index;
		begin
			rx = 1'b1;
			repeat (231) @(posedge dut.CLK);
			drive_uart_bit(1'b0);
			for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
				drive_uart_bit(value[bit_index]);
			end
			drive_uart_bit(1'b1);
		end
	endtask

	task drive_uart_bit;
		input value;
		begin
			rx = value;
			repeat (231) @(posedge dut.CLK);
		end
	endtask

	task expect_banner;
		begin
			expect_uart(8'h5a);
			expect_uart(8'h2f);
			expect_uart(8'h70);
			expect_uart(8'h64);
			expect_uart(8'h61);
			expect_uart(8'h58);
			expect_uart(8'h72);
			expect_uart(8'h6f);
			expect_uart(8'h6d);
			expect_uart(8'h0a);
			expect_uart(8'h0d);
		end
	endtask

	task check_payload;
		begin
			for (i = 0; i < PAYLOAD_LEN; i = i + 1) begin
				if (dut.srampages.Mem[i] != payload[i]) begin
					$display("FAIL: loaded byte %0d got %02x expected %02x", i, dut.srampages.Mem[i], payload[i]);
					$finish_and_return(1);
				end
			end
		end
	endtask

	task expect_uart;
		input [7:0] expected;
		reg [7:0] got;
		integer bit_index;
		begin
			got = 0;
			wait (tx === 1'b0);
			#(BIT_TIME + (BIT_TIME / 2));
			for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
				got[bit_index] = tx;
				#BIT_TIME;
			end
			if (got != expected) begin
				$display("FAIL: hc1200-mcu UART got %02x expected %02x", got, expected);
				$finish_and_return(1);
			end
		end
	endtask
endmodule

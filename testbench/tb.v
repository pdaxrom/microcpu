`timescale 1ns/1ps

module test_bench;
	localparam UART_ADDR        = 16'hffe0;
	localparam TIMER_ADDR       = 16'hfff0;
	localparam TEST_UART_EXPECT = 16'hfffc;
	localparam TEST_INTR        = 16'hfffd;
	localparam TEST_STATUS      = 16'hfffe;
	localparam TEST_PUTC        = 16'hffff;

	reg         clk;
	reg         rst;
	reg         test_intr;
	wire        intr;
	wire        read;
	wire [15:0] address;
	wire [7:0]  dout;
	wire [7:0]  din;

	reg [7:0] mem [0:65535];
	reg [7:0] uart_rx_data;
	reg       uart_rx_full;
	reg [7:0] uart_expected;
	reg       uart_expect_valid;
	integer   boot_banner_mode;
	integer   boot_banner_index;
	reg [16:0] timer_counter;
	reg        timer_intr;

	reg [1023:0] program_file;
	reg [1023:0] vcd_file;
	integer i;
	integer cycles;
	integer timeout_cycles;

	assign intr = test_intr | timer_intr;
	assign din = read ? read_data(address) : 8'hff;

	function [7:0] read_data;
		input [15:0] addr;
		begin
			if (addr == UART_ADDR) begin
				read_data = {6'b0, 1'b0, uart_rx_full};
			end else if (addr == UART_ADDR + 1) begin
				read_data = uart_rx_data;
			end else if (addr == TIMER_ADDR) begin
				read_data = timer_counter[7:0];
			end else if (addr == TIMER_ADDR + 1) begin
				read_data = timer_counter[15:8];
			end else if (addr == TIMER_ADDR + 2) begin
				read_data = {5'b0, timer_counter[16], timer_intr};
			end else begin
				read_data = mem[addr];
			end
		end
	endfunction

	function [7:0] boot_banner_char;
		input integer index;
		begin
			case (index)
			0: boot_banner_char = 8'h5a; // Z
			1: boot_banner_char = 8'h2f; // /
			2: boot_banner_char = 8'h70; // p
			3: boot_banner_char = 8'h64; // d
			4: boot_banner_char = 8'h61; // a
			5: boot_banner_char = 8'h58; // X
			6: boot_banner_char = 8'h72; // r
			7: boot_banner_char = 8'h6f; // o
			8: boot_banner_char = 8'h6d; // m
			9: boot_banner_char = 8'h0a;
			10: boot_banner_char = 8'h0d;
			default: boot_banner_char = 8'h00;
			endcase
		end
	endfunction

	cpu core1 (
		.clk(clk),
		.rst(rst),
		.read(read),
		.address(address),
		.dout(dout),
		.din(din),
		.intr(intr)
	);

	initial begin
		clk = 0;
		forever #5 clk = !clk;
	end

	initial begin
		rst = 1;
		test_intr = 0;
		uart_rx_data = 8'h52;
		uart_rx_full = 1;
		uart_expected = 0;
		uart_expect_valid = 0;
		boot_banner_mode = 0;
		boot_banner_index = 0;
		timer_counter = 17'h10000;
		timer_intr = 0;
		cycles = 0;
		timeout_cycles = 20000;

		for (i = 0; i < 65536; i = i + 1) begin
			mem[i] = 8'h00;
		end

		if (!$value$plusargs("PROGRAM=%s", program_file)) begin
			$display("FAIL: missing +PROGRAM=<hex-file>");
			$finish_and_return(1);
		end

		if ($value$plusargs("TIMEOUT=%d", timeout_cycles)) begin
			$display("timeout_cycles=%0d", timeout_cycles);
		end

		if ($test$plusargs("BOOT_BANNER")) begin
			boot_banner_mode = 1;
		end

		if ($value$plusargs("VCD=%s", vcd_file)) begin
			$dumpfile(vcd_file);
			$dumpvars(0, test_bench);
		end

		$readmemh(program_file, mem);

		repeat (4) @(posedge clk);
		rst = 0;
	end

	always @(posedge clk) begin
		if (!rst) begin
			cycles = cycles + 1;
			if (cycles > timeout_cycles) begin
				$display("FAIL: timeout after %0d cycles at address %04x", cycles, address);
				$finish_and_return(1);
			end

			if ((read !== 1'b0) && (read !== 1'b1)) begin
				$display("FAIL: read is unknown at cycle %0d", cycles);
				$finish_and_return(1);
			end

			if (^address === 1'bx) begin
				$display("FAIL: address is unknown at cycle %0d", cycles);
				$finish_and_return(1);
			end

			if (!read) begin
				if ((address >= UART_ADDR) && (^dout === 1'bx)) begin
					$display("FAIL: dout is unknown during write at cycle %0d address %04x", cycles, address);
					$finish_and_return(1);
				end

				case (address)
				TEST_STATUS: begin
					if (uart_expect_valid) begin
						$display("FAIL: pending UART expectation %02x at test end", uart_expected);
						$finish_and_return(1);
					end
					if (dout == 8'h00) begin
						$display("PASS: %0s in %0d cycles", program_file, cycles);
						$finish_and_return(0);
					end else begin
						$display("FAIL: %0s code=%0d at cycle %0d", program_file, dout, cycles);
						$finish_and_return(1);
					end
				end
				TEST_UART_EXPECT: begin
					uart_expected <= dout;
					uart_expect_valid <= 1'b1;
				end
				TEST_INTR: begin
					if (dout != 8'h00) begin
						test_intr <= 1'b1;
					end
				end
				TEST_PUTC: begin
					$write("%c", dout);
				end
				UART_ADDR + 1: begin
					if (uart_expect_valid) begin
						if (dout != uart_expected) begin
							$display("FAIL: UART TX got %02x expected %02x at cycle %0d", dout, uart_expected, cycles);
							$finish_and_return(1);
						end else begin
							uart_expect_valid <= 1'b0;
						end
					end else if (boot_banner_mode) begin
						if (dout != boot_banner_char(boot_banner_index)) begin
							$display("FAIL: boot banner byte %0d got %02x expected %02x", boot_banner_index, dout, boot_banner_char(boot_banner_index));
							$finish_and_return(1);
						end else if (boot_banner_index == 10) begin
							$write("%c", dout);
							$display("PASS: bootloader banner in %0d cycles", cycles);
							$finish_and_return(0);
						end else begin
							boot_banner_index <= boot_banner_index + 1;
						end
					end else begin
						$display("FAIL: unexpected UART TX byte %02x at cycle %0d", dout, cycles);
						$finish_and_return(1);
					end
					$write("%c", dout);
				end
				TIMER_ADDR: begin
				end
				TIMER_ADDR + 1: begin
				end
				default: begin
					mem[address] <= dout;
				end
				endcase
			end

			if (read && address == UART_ADDR + 1) begin
				uart_rx_full <= 1'b0;
			end

			if (read && address[15:2] == TIMER_ADDR[15:2] && address[1]) begin
				timer_intr <= 1'b0;
			end

			if (!read && address == TIMER_ADDR) begin
				timer_counter[7:0] <= dout;
			end else if (!read && address == TIMER_ADDR + 1) begin
				timer_counter[16:8] <= {1'b0, dout};
			end else if (timer_counter != 17'h10000) begin
				if (timer_counter == 17'h00001) begin
					timer_counter <= 17'h10000;
					timer_intr <= 1'b1;
				end else begin
					timer_counter <= timer_counter - 1;
				end
			end

			if (test_intr && read && address == 16'h0002) begin
				test_intr <= 1'b0;
			end
		end
	end
endmodule

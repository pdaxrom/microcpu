`timescale 1ns/1ps

module test_bench;
	localparam UART_ADDR        = 16'hffe0;
	localparam GPIO_ADDR        = 16'hffe8;
	localparam TIMER_ADDR       = 16'hfff0;
	localparam TEST_EXPECT_READ_ADDR_LO = 16'hfff4;
	localparam TEST_EXPECT_READ_ADDR_HI = 16'hfff5;
	localparam TEST_EXPECT_READ_DATA    = 16'hfff6;
	localparam TEST_EXPECT_READ_COMMIT  = 16'hfff7;
	localparam TEST_EXPECT_ADDR_LO = 16'hfff8;
	localparam TEST_EXPECT_ADDR_HI = 16'hfff9;
	localparam TEST_EXPECT_DATA    = 16'hfffa;
	localparam TEST_EXPECT_COMMIT  = 16'hfffb;
	localparam TEST_UART_EXPECT = 16'hfffc;
	localparam TEST_INTR        = 16'hfffd;
	localparam TEST_STATUS      = 16'hfffe;
	localparam TEST_PUTC        = 16'hffff;
	localparam BOOT_NONE        = 0;
	localparam BOOT_BANNER      = 1;
	localparam BOOT_SAVE        = 2;
	localparam BOOT_GO          = 3;
	localparam BOOT_LOAD        = 4;

	reg         clk;
	reg         rst;
	reg         test_intr;
	reg         test_intr_delay_active;
	integer     test_intr_delay;
	wire        intr;
	wire        read;
	wire [15:0] address;
	wire [7:0]  dout;
	wire [7:0]  din;

	reg [7:0] mem [0:65535];
	reg [7:0] uart_rx_data;
	reg       uart_rx_full;
	reg [7:0] uart_rx_queue [0:255];
	integer   uart_rx_len;
	integer   uart_rx_index;
	reg [7:0] uart_expected;
	reg       uart_expect_valid;
	integer   boot_mode;
	integer   boot_output_index;
	reg [14:0] gpio_out;
	reg [14:0] gpio_dir;
	reg [16:0] timer_counter;
	reg        timer_intr;
	reg [15:0] expect_addr_tmp;
	reg [7:0]  expect_data_tmp;
	reg [15:0] expect_addr [0:15];
	reg [7:0]  expect_data [0:15];
	integer   expect_count;
	reg [15:0] expect_read_addr_tmp;
	reg [7:0]  expect_read_data_tmp;
	reg [15:0] expect_read_addr [0:15];
	reg [7:0]  expect_read_data [0:15];
	integer   expect_read_count;

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
			end else if (addr == GPIO_ADDR) begin
				read_data = {1'b1, gpio_out[14:8]};
			end else if (addr == GPIO_ADDR + 1) begin
				read_data = gpio_out[7:0];
			end else if (addr == GPIO_ADDR + 2) begin
				read_data = {1'b1, gpio_dir[14:8]};
			end else if (addr == GPIO_ADDR + 3) begin
				read_data = gpio_dir[7:0];
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

	function [7:0] boot_save_char;
		input integer index;
		begin
			case (index)
			0: boot_save_char = 8'hde;
			1: boot_save_char = 8'had;
			2: boot_save_char = 8'hbe;
			3: boot_save_char = 8'hef;
			default: boot_save_char = 8'h00;
			endcase
		end
	endfunction

	task uart_queue_push;
		input [7:0] value;
		begin
			uart_rx_queue[uart_rx_len] = value;
			uart_rx_len = uart_rx_len + 1;
		end
	endtask

	task uart_queue_start;
		begin
			uart_rx_index = 0;
			if (uart_rx_len > 0) begin
				uart_rx_data = uart_rx_queue[0];
				uart_rx_full = 1;
			end else begin
				uart_rx_full = 0;
			end
		end
	endtask

	task setup_boot_save;
		begin
			boot_mode = BOOT_SAVE;
			uart_rx_len = 0;
			uart_queue_push(8'h53); // S
			uart_queue_push(8'h08);
			uart_queue_push(8'h00);
			uart_queue_push(8'h08);
			uart_queue_push(8'h04);
			uart_queue_start();
		end
	endtask

	task setup_boot_go;
		begin
			boot_mode = BOOT_GO;
			uart_rx_len = 0;
			uart_queue_push(8'h47); // G
			uart_queue_push(8'h08);
			uart_queue_push(8'h00);
			uart_queue_start();
		end
	endtask

	task setup_boot_load;
		begin
			boot_mode = BOOT_LOAD;
			uart_rx_len = 0;
			uart_queue_push(8'h4c); // L
			uart_queue_push(8'h08);
			uart_queue_push(8'h00);
			uart_queue_push(8'h08);
			uart_queue_push(8'h04);
			uart_queue_push(8'ha0);
			uart_queue_push(8'ha1);
			uart_queue_push(8'ha2);
			uart_queue_push(8'ha3);
			uart_queue_push(8'h00);
			uart_queue_push(8'h00);
			uart_queue_push(8'h00);
			uart_queue_push(8'h00);
			uart_queue_push(8'h00);
			uart_queue_push(8'h00);
			uart_queue_push(8'h00);
			uart_queue_push(8'h00);
			uart_queue_push(8'h00);
			uart_queue_push(8'h00);
			uart_queue_start();
		end
	endtask

	task expect_push;
		begin
			if (expect_count == 16) begin
				$display("FAIL: expected write queue overflow");
				$finish_and_return(1);
			end
			expect_addr[expect_count] = expect_addr_tmp;
			expect_data[expect_count] = expect_data_tmp;
			expect_count = expect_count + 1;
		end
	endtask

	task expect_check;
		input [15:0] addr;
		input [7:0] data;
		integer j;
		begin
			if (expect_count > 0) begin
				if (addr != expect_addr[0] || data != expect_data[0]) begin
					$display("FAIL: write got %04x=%02x expected %04x=%02x at cycle %0d",
						addr, data, expect_addr[0], expect_data[0], cycles);
					$finish_and_return(1);
				end
				for (j = 0; j < 15; j = j + 1) begin
					expect_addr[j] = expect_addr[j + 1];
					expect_data[j] = expect_data[j + 1];
				end
				expect_count = expect_count - 1;
			end
		end
	endtask

	task expect_read_push;
		begin
			if (expect_read_count == 16) begin
				$display("FAIL: expected read queue overflow");
				$finish_and_return(1);
			end
			expect_read_addr[expect_read_count] = expect_read_addr_tmp;
			expect_read_data[expect_read_count] = expect_read_data_tmp;
			expect_read_count = expect_read_count + 1;
		end
	endtask

	task expect_read_check;
		input [15:0] addr;
		input [7:0] data;
		integer j;
		begin
			if (expect_read_count > 0 && addr == expect_read_addr[0]) begin
				if (data != expect_read_data[0]) begin
					$display("FAIL: read got %04x=%02x expected %04x=%02x at cycle %0d",
						addr, data, expect_read_addr[0], expect_read_data[0], cycles);
					$finish_and_return(1);
				end
				for (j = 0; j < 15; j = j + 1) begin
					expect_read_addr[j] = expect_read_addr[j + 1];
					expect_read_data[j] = expect_read_data[j + 1];
				end
				expect_read_count = expect_read_count - 1;
			end
		end
	endtask

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
		test_intr_delay_active = 0;
		test_intr_delay = 0;
		uart_rx_data = 8'h52;
		uart_rx_full = 1;
		uart_rx_len = 0;
		uart_rx_index = 0;
		uart_expected = 0;
		uart_expect_valid = 0;
		boot_mode = BOOT_NONE;
		boot_output_index = 0;
		gpio_out = 0;
		gpio_dir = 0;
		timer_counter = 17'h10000;
		timer_intr = 0;
		expect_addr_tmp = 0;
		expect_data_tmp = 0;
		expect_count = 0;
		expect_read_addr_tmp = 0;
		expect_read_data_tmp = 0;
		expect_read_count = 0;
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
			boot_mode = BOOT_BANNER;
		end

		if ($test$plusargs("BOOT_SAVE")) begin
			setup_boot_save();
		end

		if ($test$plusargs("BOOT_GO")) begin
			setup_boot_go();
		end

		if ($test$plusargs("BOOT_LOAD")) begin
			setup_boot_load();
		end

		if ($value$plusargs("VCD=%s", vcd_file)) begin
			$dumpfile(vcd_file);
			$dumpvars(0, test_bench);
		end

		$readmemh(program_file, mem);

		if (boot_mode == BOOT_SAVE) begin
			mem[16'h0800] = 8'hde;
			mem[16'h0801] = 8'had;
			mem[16'h0802] = 8'hbe;
			mem[16'h0803] = 8'hef;
		end else if (boot_mode == BOOT_GO) begin
			mem[16'h0800] = 8'h46;
			mem[16'h0801] = 8'hfe;
			mem[16'h0802] = 8'h56;
			mem[16'h0803] = 8'hff;
			mem[16'h0804] = 8'h47;
			mem[16'h0805] = 8'h00;
			mem[16'h0806] = 8'h17;
			mem[16'h0807] = 8'hc1;
			mem[16'h0808] = 8'hb0;
			mem[16'h0809] = 8'h00;
		end else if (boot_mode == BOOT_LOAD) begin
			mem[16'h0800] = 8'h00;
			mem[16'h0801] = 8'h00;
			mem[16'h0802] = 8'h00;
			mem[16'h0803] = 8'h00;
		end

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
					if (expect_count != 0) begin
						$display("FAIL: %0d expected write(s) still pending at test end", expect_count);
						$finish_and_return(1);
					end
					if (expect_read_count != 0) begin
						$display("FAIL: %0d expected read(s) still pending at test end", expect_read_count);
						$finish_and_return(1);
					end
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
				TEST_EXPECT_READ_ADDR_LO: begin
					expect_read_addr_tmp[7:0] <= dout;
				end
				TEST_EXPECT_READ_ADDR_HI: begin
					expect_read_addr_tmp[15:8] <= dout;
				end
				TEST_EXPECT_READ_DATA: begin
					expect_read_data_tmp <= dout;
				end
				TEST_EXPECT_READ_COMMIT: begin
					expect_read_push();
				end
				TEST_EXPECT_ADDR_LO: begin
					expect_addr_tmp[7:0] <= dout;
				end
				TEST_EXPECT_ADDR_HI: begin
					expect_addr_tmp[15:8] <= dout;
				end
				TEST_EXPECT_DATA: begin
					expect_data_tmp <= dout;
				end
				TEST_EXPECT_COMMIT: begin
					expect_push();
				end
				TEST_UART_EXPECT: begin
					uart_expected <= dout;
					uart_expect_valid <= 1'b1;
				end
				TEST_INTR: begin
					if (dout == 8'h00) begin
						test_intr <= 1'b0;
						test_intr_delay_active <= 1'b0;
					end else if (dout == 8'h01) begin
						test_intr <= 1'b1;
					end else begin
						test_intr_delay <= dout;
						test_intr_delay_active <= 1'b1;
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
					end else if (boot_mode != BOOT_NONE) begin
						if (boot_output_index < 11) begin
							if (dout != boot_banner_char(boot_output_index)) begin
								$display("FAIL: boot banner byte %0d got %02x expected %02x", boot_output_index, dout, boot_banner_char(boot_output_index));
								$finish_and_return(1);
							end else if (boot_output_index == 10) begin
								if (boot_mode == BOOT_BANNER) begin
									$write("%c", dout);
									$display("PASS: bootloader banner in %0d cycles", cycles);
									$finish_and_return(0);
								end else if (boot_mode == BOOT_GO) begin
									boot_mode <= BOOT_NONE;
								end
							end
						end else if (boot_mode == BOOT_SAVE) begin
							if (dout != boot_save_char(boot_output_index - 11)) begin
								$display("FAIL: boot save byte %0d got %02x expected %02x", boot_output_index - 11, dout, boot_save_char(boot_output_index - 11));
								$finish_and_return(1);
							end else if (boot_output_index == 14) begin
								$display("PASS: bootloader save in %0d cycles", cycles);
								$finish_and_return(0);
							end
						end else if (boot_mode == BOOT_LOAD) begin
							if (dout != 8'ha3) begin
								$display("FAIL: boot load echo got %02x expected a3", dout);
								$finish_and_return(1);
							end else if (mem[16'h0800] != 8'ha0 ||
							            mem[16'h0801] != 8'ha1 ||
							            mem[16'h0802] != 8'ha2 ||
							            mem[16'h0803] != 8'ha3) begin
								$display("FAIL: boot load memory got %02x %02x %02x %02x",
									mem[16'h0800], mem[16'h0801], mem[16'h0802], mem[16'h0803]);
								$finish_and_return(1);
							end else begin
								$display("PASS: bootloader load in %0d cycles", cycles);
								$finish_and_return(0);
							end
						end else begin
							$display("FAIL: unexpected boot UART TX byte %02x at index %0d", dout, boot_output_index);
							$finish_and_return(1);
						end
						boot_output_index <= boot_output_index + 1;
					end else begin
						$display("FAIL: unexpected UART TX byte %02x at cycle %0d", dout, cycles);
						$finish_and_return(1);
					end
					if (!(boot_mode == BOOT_SAVE && boot_output_index >= 11)) begin
						$write("%c", dout);
					end
				end
				GPIO_ADDR: begin
					gpio_out[14:8] <= dout[6:0];
				end
				GPIO_ADDR + 1: begin
					gpio_out[7:0] <= dout;
				end
				GPIO_ADDR + 2: begin
					gpio_dir[14:8] <= dout[6:0];
				end
				GPIO_ADDR + 3: begin
					gpio_dir[7:0] <= dout;
				end
				TIMER_ADDR: begin
				end
				TIMER_ADDR + 1: begin
				end
				default: begin
					expect_check(address, dout);
					mem[address] <= dout;
				end
				endcase
			end

			if (test_intr_delay_active) begin
				if (test_intr_delay == 0) begin
					test_intr <= 1'b1;
					test_intr_delay_active <= 1'b0;
				end else begin
					test_intr_delay <= test_intr_delay - 1;
				end
			end

			if (read) begin
				expect_read_check(address, din);
			end

			if (read && address == UART_ADDR + 1) begin
				if (uart_rx_len > 0 && uart_rx_index + 1 < uart_rx_len) begin
					uart_rx_index <= uart_rx_index + 1;
					uart_rx_data <= uart_rx_queue[uart_rx_index + 1];
					uart_rx_full <= 1'b1;
				end else begin
					uart_rx_full <= 1'b0;
				end
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

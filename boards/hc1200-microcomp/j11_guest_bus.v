`timescale 1ns/1ps

// Native services for firmware. There are no PDP-11 addresses, CSR bits,
	// interrupt enables, priorities, or vectors in this adapter.
module j11_hc1200_guest_bus #(
	parameter integer FRAM_CLK_DIV = 2,
	parameter integer TICK_DIVISOR = 443333
) (
	input wire clk, rst, guest_reset,
	input wire req, write, byte_access, bank,
	input wire [15:0] address, wdata,
	output wire [15:0] rdata,
	output wire ready, error, busy,
	input wire uart_rx,
	output wire uart_tx,
	output wire irq,
	output wire [2:0] irq_level,
	output wire [7:0] irq_vector,
	output wire spi_cs_n, spi_sck, spi_mosi,
	input wire spi_miso
);
	// Private firmware ABI, blocked from guest accesses by the microcode:
	// F000 status: RX byte available (bit 0), TX ready (bit 1).
	// F002 data: consume RX byte / submit TX byte.
	// F004 time: free-running 16-bit tick sequence, unaffected by guest RESET.
	// F006 control: pulse UART reset (bit 0), TX space (bit 1), loopback (bit 2).
	wire io_page = !bank && address[15:13] == 3'b111;
	wire native_selected = io_page && address[15:3] == 13'h1e00;
	wire fram_selected = bank || !io_page;
	wire low_lane = !byte_access || !address[0];
	wire odd_word = !byte_access && address[0];
	wire [15:0] fram_rdata;
	wire fram_ready, fram_error, fram_busy;
	reg [15:0] native_rdata;
	reg native_ready, native_error, request_seen;
	reg uart_cs, uart_reset;
	reg [2:1] uart_control;
	wire [7:0] uart_data;
	wire uart_rx_ready, uart_tx_ready, serial_tx;
	localparam integer TICK_WIDTH = TICK_DIVISOR > 1 ? $clog2(TICK_DIVISOR) : 1;
	reg [TICK_WIDTH-1:0] tick_divider;
	reg [15:0] ticks;
	reg event_pending, previous_tx_ready;
	wire tick_event = tick_divider == TICK_DIVISOR - 1;
	wire status_read = req && native_selected && !request_seen &&
		!odd_word && !write && low_lane && address[2:1] == 0;

	spi_fram_guest_ram #(.CLK_DIV(FRAM_CLK_DIV)) fram (
		.clk(clk), .rst(rst), .req(req && fram_selected), .write(write),
		.byte_access(byte_access), .bank(bank), .address(address), .wdata(wdata),
		.rdata(fram_rdata), .ready(fram_ready), .error(fram_error), .busy(fram_busy),
		.spi_cs_n(spi_cs_n), .spi_sck(spi_sck), .spi_mosi(spi_mosi), .spi_miso(spi_miso)
	);
	uart console (
		.clk(clk), .reset(rst || guest_reset || uart_reset), .a0(1'b1),
		.din(wdata[7:0]), .dout(uart_data), .rnw(!write), .cs(uart_cs),
		.rxd(uart_control[2] ? uart_tx : uart_rx), .txd(serial_tx),
		.rx_ready(uart_rx_ready), .tx_ready(uart_tx_ready)
	);
	assign uart_tx = uart_control[1] ? 1'b0 : serial_tx;
	assign rdata = fram_selected ? fram_rdata : native_rdata;
	assign ready = fram_selected ? fram_ready : native_ready;
	assign error = fram_selected ? fram_error : native_error;
	assign busy = fram_busy || (req && io_page && !native_ready);
	// Native service notification, not a guest interrupt: BR0/vector0 can never
	// pass the guest IPL check. Firmware consumes it before guest arbitration.
	// RX stays asserted until consumed, so a byte held behind a full software
	// RBUF is not lost when the guest later frees that buffer.
	assign irq = uart_rx_ready || event_pending;
	assign irq_level = 3'b0;
	assign irq_vector = 8'b0;

	always @(posedge clk) begin
		if (rst) begin
			tick_divider <= 0;
			ticks <= 0;
		end else if (tick_event) begin
			tick_divider <= 0;
			ticks <= ticks + 1'b1;
		end else tick_divider <= tick_divider + 1'b1;
	end

	always @(posedge clk) begin
		if (rst || guest_reset) begin
			event_pending <= 1;
			previous_tx_ready <= 0;
		end else begin
			previous_tx_ready <= uart_tx_ready;
			if (status_read) event_pending <= 0;
			// New events win over acknowledgement in the same cycle.
			if (tick_event || (uart_tx_ready && !previous_tx_ready))
				event_pending <= 1;
		end
	end

	always @(posedge clk) begin
		if (rst || guest_reset) begin
			native_rdata <= 0;
			native_ready <= 0;
			native_error <= 0;
			request_seen <= 0;
			uart_cs <= 0;
			uart_reset <= 0;
			uart_control <= 0;
		end else begin
			native_ready <= 0;
			native_error <= 0;
			uart_cs <= 0;
			uart_reset <= 0;
			if (!req) request_seen <= 0;
			if (req && io_page && !request_seen) begin
				request_seen <= 1;
				native_ready <= 1;
				native_rdata <= 0;
				if (odd_word || !native_selected) native_error <= 1;
				else case (address[2:1])
				0: if (!write && low_lane)
					native_rdata <= {14'b0, uart_tx_ready, uart_rx_ready};
				1: if (low_lane) begin
					native_rdata <= {8'b0, uart_data};
					uart_cs <= 1;
				end
				2: if (!write) native_rdata <= byte_access ?
					(address[0] ? {8'b0, ticks[15:8]} : {8'b0, ticks[7:0]}) : ticks;
				3: if (low_lane) begin
					if (write) begin
						uart_reset <= wdata[0];
						uart_control <= wdata[2:1];
					end else native_rdata <= {13'b0, uart_control, 1'b0};
				end
				endcase
			end
		end
	end
endmodule

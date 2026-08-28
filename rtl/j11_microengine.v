`timescale 1ns/1ps

// Diamond uses the generated, explicitly packed MachXO2 code/context RAM. The same path
// can be selected in Icarus with -DJ11_EBR_UROM and Lattice's EBR models.
`ifdef SYNTHESIS
`define J11_EBR_UROM
`endif

module j11_microengine #(
	parameter integer UROM_WORDS = 3584,
	parameter UCODE_FILE = "",
	parameter [15:0] BUS_ERROR_PC = 16'h0002
) (
	input  wire        clk,
	input  wire        rst,

	output reg         guest_req,
	output reg         guest_write,
	output reg         guest_byte,
	output reg         guest_bank,
	output reg  [15:0] guest_address,
	output reg  [15:0] guest_wdata,
	input  wire [15:0] guest_rdata,
	input  wire        guest_ready,
	input  wire        guest_error,

	input  wire        irq,
	input  wire [2:0]  irq_level,
	input  wire [7:0]  irq_vector,
	output reg         guest_reset,

	output wire [15:0] debug_upc,
	output wire [15:0] debug_guest_r0,
	output wire [15:0] debug_guest_pc,
	output wire [15:0] debug_guest_psw,
	output wire [15:0] debug_guest_ir,
	output wire [15:0] debug_cause,
	output wire [15:0] debug_pending_irq
);

	localparam [4:0] CTX_R0      = 5'd0;
	localparam [4:0] CTX_PC      = 5'd7;
	localparam [4:0] CTX_PSW     = 5'd8;
	localparam [4:0] CTX_IR      = 5'd9;
	localparam [4:0] CTX_CAUSE   = 5'd10;
	localparam [4:0] CTX_PENDING = 5'd11;
	localparam [4:0] CTX_CONTROL = 5'd15;

	localparam [3:0] ST_CLEAR    = 4'd0;
	localparam [3:0] ST_FETCH    = 4'd1;
	localparam [3:0] ST_READ_A   = 4'd2;
	localparam [3:0] ST_READ_B   = 4'd3;
	localparam [3:0] ST_READ_D   = 4'd4;
	localparam [3:0] ST_PRE_EXEC = 4'd5;
	localparam [3:0] ST_EXEC     = 4'd6;
	localparam [3:0] ST_MEM      = 4'd7;
	localparam [3:0] ST_SHIFT    = 4'd8;

	localparam [3:0] INST_LDRL  = 4'h0;
	localparam [3:0] INST_STRL  = 4'h1;
	localparam [3:0] INST_LDR   = 4'h2;
	localparam [3:0] INST_STR   = 4'h3;
	localparam [3:0] INST_SETL  = 4'h4;
	localparam [3:0] INST_SETH  = 4'h5;
	localparam [3:0] INST_MOVL  = 4'h6;
	localparam [3:0] INST_MOVH  = 4'h7;
	localparam [3:0] INST_MOV   = 4'h8;
	localparam [3:0] INST_GGET  = 4'h9;
	localparam [3:0] INST_GSET  = 4'ha;
	localparam [3:0] INST_B     = 4'hb;
	localparam [3:0] INST_GGETR = 4'hc;
	localparam [3:0] INST_GSETR = 4'hd;
	localparam [3:0] INST_GETF  = 4'he;

	localparam [3:0] ALU_CMP  = 4'h0;
	localparam [3:0] ALU_BIT  = 4'h1;
	localparam [3:0] ALU_SEXT = 4'h4;
	localparam [3:0] ALU_SUBB = 4'h5;
	localparam [3:0] ALU_ADD  = 4'h8;
	localparam [3:0] ALU_SUB  = 4'h9;
	localparam [3:0] ALU_SHL  = 4'ha;
	localparam [3:0] ALU_SHR  = 4'hb;
	localparam [3:0] ALU_AND  = 4'hc;
	localparam [3:0] ALU_OR   = 4'hd;
	localparam [3:0] ALU_INV  = 4'he;
	localparam [3:0] ALU_XOR  = 4'hf;

	localparam [2:0] CMP_EQ  = 3'd0;
	localparam [2:0] CMP_NE  = 3'd1;
	localparam [2:0] CMP_MI  = 3'd2;
	localparam [2:0] CMP_VS  = 3'd3;
	localparam [2:0] CMP_LT  = 3'd4;
	localparam [2:0] CMP_GE  = 3'd5;
	localparam [2:0] CMP_LTU = 3'd6;
	localparam [2:0] CMP_GEU = 3'd7;

	// Only the eight native working registers use distributed RAM. The generic
	// 64-word context occupies the tail of the same EBRs as the microcode.
	reg [15:0] r [0:7]
		/* synthesis syn_ramstyle = "distributed" */;

	reg [15:0] uir;
	wire [15:0] memory_read_data;
	reg [15:0] upc;
	reg [15:0] host_read_data;
	reg [15:0] operand_a;
	reg [15:0] operand_b;
	reg [3:0] alu_flags;
	reg [3:0] state;
	reg [5:0] clear_index;

	reg [4:0] shift_count;

	/* Fixed debug mirrors avoid extra read ports on the context RAM. */
	reg [15:0] guest_r0_mirror;
	reg [15:0] guest_pc_mirror;
	reg [15:0] guest_psw_mirror;
	reg [15:0] guest_ir_mirror;
	reg [15:0] cause_reg;
	reg [15:0] pending_irq_reg;

	wire [4:0] op = uir[7:3];
	wire [2:0] dest = uir[2:0];
	wire [3:0] kind = op[4:1];
	wire [2:0] arg1 = uir[15:13];
	wire [2:0] arg2 = uir[12:10];
	wire [3:0] const4 = uir[12:9];
	wire is_const4 = uir[8];
	wire [7:0] immediate8 = uir[15:8];
	wire [4:0] context_index = uir[12:8];
	wire [15:0] exec_pc = upc + 1'b1;
	// The read address stays at dest after ST_READ_D, so the synchronous RAM
	// output already holds the destination operand throughout ST_EXEC.
	wire [15:0] operand_dest = dest == 0 ? exec_pc : host_read_data;
	// A single relative-PC adder handles fall-through, compare/bit skips and
	// signed branches. Other instructions always select the ordinary +2.
	wire relative_branch = !op[0] && kind == INST_B;
	wire conditional_skip = op[0] && (kind == ALU_CMP || kind == ALU_BIT);
	wire [15:0] pc_step = relative_branch ?
		{{4{dest[2]}}, dest, immediate8, 1'b0} :
		(conditional_skip && compare_true(dest,
			{flag_n, flag_z, flag_v_sub, flag_c}) ? 16'd4 : 16'd2);
	wire [15:0] next_pc = upc + pc_step;
	localparam integer UROM_ADDR_WIDTH = $clog2(UROM_WORDS);
	localparam integer CONTEXT_BASE = UROM_WORDS - 64;
	wire [UROM_ADDR_WIDTH-1:0] fetch_address =
		upc[UROM_ADDR_WIDTH:1];

	reg [2:0] host_read_address;
	always @* begin
		case (state)
		// Fetch has just completed; read A from that word while latching uIR.
		// Later context reads may overwrite memory_read_data, but not uIR.
		ST_READ_A: host_read_address = memory_read_data[15:13];
		ST_READ_B: host_read_address = arg2;
		default:   host_read_address = dest;
		endcase
	end

	// Immediate instructions retain their five-bit encoding. Indexed access
	// reaches all 64 words; their meaning and bank switching stay in firmware.
	wire [5:0] dynamic_context_index = operand_a[5:0];
	wire context_is_dynamic =
		kind == INST_GGETR || kind == INST_GSETR;
	wire [5:0] context_access_index = context_is_dynamic ?
		dynamic_context_index : {1'b0, context_index};
	wire context_read_enable = state == ST_READ_D && !op[0] &&
		(kind == INST_GGET || kind == INST_GGETR);
	wire memory_read_enable = !rst && (state == ST_FETCH || context_read_enable);
	wire [UROM_ADDR_WIDTH-1:0] memory_read_address = state == ST_FETCH ?
		fetch_address : (CONTEXT_BASE | context_access_index);
	wire [15:0] context_read_value =
		context_access_index == CTX_CAUSE ? cause_reg :
		context_access_index == CTX_PENDING ? pending_irq_reg :
		memory_read_data;

	reg host_write_enable;
	reg host_write_low;
	reg host_write_high;
	reg [2:0] host_write_address;
	reg [15:0] host_write_data;

	reg context_write_enable;
	reg [5:0] context_write_address;
	reg [15:0] context_write_data;

	reg [16:0] alu_result;
	reg [8:0] alu_byte_result;
	// Shared add/subtract datapath also generates native load/store addresses.
	// Invert the extended B operand for subtraction so bit 16 stays borrow,
	// matching the native ALU ABI (rather than the adder's not-borrow carry).
	wire arithmetic_subtract = op[0] && kind != ALU_ADD;
	wire [16:0] arithmetic_result = {1'b0, operand_a} +
		{arithmetic_subtract, operand_b ^ {16{arithmetic_subtract}}} +
		arithmetic_subtract;
	wire byte_borrow = (!operand_a[7] && operand_b[7]) ||
		((!operand_a[7] || operand_b[7]) && arithmetic_result[7]);
	wire flag_z = alu_result[15:0] == 0;
	wire flag_c = alu_result[16];
	wire flag_n = alu_result[15];
	wire flag_v_sub = ((operand_a ^ operand_b) &
		(operand_a ^ alu_result[15:0]) & 16'h8000) != 0;
	wire flag_v_add = ((~(operand_a ^ operand_b)) &
		(operand_a ^ alu_result[15:0]) & 16'h8000) != 0;
	wire flag_byte_v_sub = (operand_a[7] ^ operand_b[7]) &&
		(operand_a[7] ^ alu_byte_result[7]);
	reg [3:0] alu_next_flags;

	wire [4:0] initial_shift_count =
		(|operand_b[15:5] || operand_b[4:0] > 5'd17) ?
		5'd17 : operand_b[4:0];
	// Reuse operand A as the iterative shifter; uIR keeps the direction.
	wire shift_left = kind == ALU_SHL;
	wire [15:0] shifted_value = shift_left ?
		{operand_a[14:0], 1'b0} : {1'b0, operand_a[15:1]};
	wire shift_carry = shift_left && operand_a[15];

	`ifdef J11_EBR_UROM
	wire [11:0] ebr_address = memory_read_address;
	j11_urom_ebr #(.WORDS(UROM_WORDS)) microcode_rom (
		.clk(clk), .rst(rst), .enable(memory_read_enable),
		.address(ebr_address), .data(memory_read_data),
		.write_enable(context_write_enable && !rst),
		.write_address(context_write_address), .write_data(context_write_data)
	);
	`else
	reg [15:0] urom [0:UROM_WORDS-1];
	reg [15:0] urom_data;
	integer i;
	initial begin
		for (i = 0; i < UROM_WORDS; i = i + 1) begin
			urom[i] = i < CONTEXT_BASE ? 16'h00b0 : 16'h0000;
		end
		if (UCODE_FILE != "") begin
			$readmemh(UCODE_FILE, urom);
		end
	end
	always @(posedge clk) begin
		if (rst) urom_data <= 0;
		else if (memory_read_enable) urom_data <= urom[memory_read_address];
		// The write address cannot reach code, including during reset clearing.
		if (!rst && context_write_enable)
			urom[CONTEXT_BASE | context_write_address] <= context_write_data;
	end
	assign memory_read_data = urom_data;
	`endif

	function compare_true;
		input [2:0] condition;
		input [3:0] flags;
		begin
			case (condition)
			CMP_EQ:  compare_true = flags[2];
			CMP_NE:  compare_true = !flags[2];
			CMP_MI:  compare_true = flags[3];
			CMP_VS:  compare_true = flags[1];
			CMP_LT:  compare_true = flags[3] ^ flags[1];
			CMP_GE:  compare_true = !(flags[3] ^ flags[1]);
			CMP_LTU: compare_true = flags[0];
			CMP_GEU: compare_true = !flags[0];
			default: compare_true = 0;
			endcase
		end
	endfunction

	/* Variable shifts are handled iteratively in ST_SHIFT. */
	always @* begin
		alu_byte_result = 0;
		case (kind)
		ALU_SEXT: alu_result = {1'b0, {8{operand_a[7]}}, operand_a[7:0]};
		ALU_SUBB: begin
			alu_byte_result = {byte_borrow, arithmetic_result[7:0]};
			alu_result = {9'b0, alu_byte_result[7:0]};
		end
		ALU_ADD,
		ALU_CMP,
		ALU_SUB:  alu_result = arithmetic_result;
		ALU_BIT,
		ALU_AND:  alu_result = {1'b0, operand_a & operand_b};
		ALU_OR:   alu_result = {1'b0, operand_a | operand_b};
		ALU_INV:  alu_result = {1'b0, ~operand_a};
		ALU_XOR:  alu_result = {1'b0, operand_a ^ operand_b};
		default:  alu_result = {1'b0, operand_a};
		endcase
	end

	always @* begin
		case (kind)
		ALU_ADD: alu_next_flags = {flag_n, flag_z, flag_v_add, flag_c};
		ALU_CMP,
		ALU_SUB: alu_next_flags = {flag_n, flag_z, flag_v_sub, flag_c};
		ALU_SUBB: alu_next_flags = {
			alu_byte_result[7],
			alu_byte_result[7:0] == 0,
			flag_byte_v_sub,
			alu_byte_result[8]
		};
		default: alu_next_flags = {flag_n, flag_z, 1'b0, flag_c};
		endcase
	end

	/* One synchronous read port and one byte-enabled write port. */
	always @(posedge clk) begin
		host_read_data <= r[host_read_address];
		if (host_write_enable) begin
			if (host_write_low) begin
				r[host_write_address][7:0] <= host_write_data[7:0];
			end
			if (host_write_high) begin
				r[host_write_address][15:8] <= host_write_data[15:8];
			end
		end
	end

	/* Centralized native-register and shared-memory write ports. */
	always @* begin
		host_write_enable = 0;
		host_write_low = 0;
		host_write_high = 0;
		host_write_address = dest;
		host_write_data = 0;

		if (state == ST_CLEAR && clear_index < 8) begin
			host_write_enable = 1;
			host_write_low = 1;
			host_write_high = 1;
			host_write_address = clear_index[2:0];
			host_write_data = 0;
		end else if (state == ST_EXEC && !op[0] && dest != 0) begin
			case (kind)
			INST_SETL: begin
				host_write_enable = 1;
				host_write_low = 1;
				host_write_data = {8'b0, immediate8};
			end
			INST_SETH: begin
				host_write_enable = 1;
				host_write_high = 1;
				host_write_data = {immediate8, 8'b0};
			end
			INST_MOVL: begin
				host_write_enable = 1;
				host_write_low = 1;
				host_write_data = {8'b0, operand_a[7:0]};
			end
			INST_MOVH: begin
				host_write_enable = 1;
				host_write_high = 1;
				host_write_data = {operand_a[7:0], 8'b0};
			end
			INST_MOV: begin
				host_write_enable = 1;
				host_write_low = 1;
				host_write_high = 1;
				host_write_data = operand_a;
			end
			INST_GGET,
			INST_GGETR: begin
				host_write_enable = 1;
				host_write_low = 1;
				host_write_high = 1;
				host_write_data = context_read_value;
			end
			INST_GETF: begin
				host_write_enable = 1;
				host_write_low = 1;
				host_write_high = 1;
				host_write_data = {12'b0, alu_flags};
			end
			default: begin
				host_write_enable = 0;
			end
			endcase
		end else if (state == ST_EXEC && op[0] &&
				kind != ALU_CMP && kind != ALU_BIT &&
				kind != ALU_SHL && kind != ALU_SHR && dest != 0) begin
			host_write_enable = 1;
			host_write_low = 1;
			host_write_high = 1;
			host_write_data = alu_result[15:0];
		end else if (state == ST_EXEC && op[0] &&
				(kind == ALU_SHL || kind == ALU_SHR) &&
				initial_shift_count == 0 && dest != 0) begin
			host_write_enable = 1;
			host_write_low = 1;
			host_write_high = 1;
			host_write_data = operand_a;
		end else if (state == ST_SHIFT && shift_count == 1 && dest != 0) begin
			host_write_enable = 1;
			host_write_low = 1;
			host_write_high = 1;
			host_write_data = shifted_value;
		end else if (state == ST_MEM && guest_ready && !guest_error &&
				(kind == INST_LDRL || kind == INST_LDR) && dest != 0) begin
			host_write_enable = 1;
			host_write_low = 1;
			host_write_high = kind == INST_LDR;
			host_write_data = guest_rdata;
		end
	end

	always @* begin
		context_write_enable = 0;
		context_write_address = clear_index;
		context_write_data = 0;

		if (state == ST_CLEAR) begin
			context_write_enable = 1;
		end else if (state == ST_EXEC && !op[0] &&
				(kind == INST_GSET || kind == INST_GSETR) &&
				context_access_index != CTX_CAUSE &&
				context_access_index != CTX_PENDING &&
				context_access_index != CTX_CONTROL) begin
			context_write_enable = 1;
			context_write_address = context_access_index;
			context_write_data = operand_dest;
		end
	end

	assign debug_upc = upc;
	assign debug_guest_r0 = guest_r0_mirror;
	assign debug_guest_pc = guest_pc_mirror;
	assign debug_guest_psw = guest_psw_mirror;
	assign debug_guest_ir = guest_ir_mirror;
	assign debug_cause = cause_reg;
	assign debug_pending_irq = pending_irq_reg;

	always @(posedge clk) begin
		if (rst) begin
			upc <= 0;
			uir <= 0;
			state <= ST_CLEAR;
			clear_index <= 0;
			guest_req <= 0;
			guest_write <= 0;
			guest_byte <= 0;
			guest_bank <= 0;
			guest_address <= 0;
			guest_wdata <= 0;
			operand_a <= 0;
			operand_b <= 0;
			shift_count <= 0;
			alu_flags <= 0;
			guest_r0_mirror <= 0;
			guest_pc_mirror <= 0;
			guest_psw_mirror <= 0;
			guest_ir_mirror <= 0;
			cause_reg <= 0;
			pending_irq_reg <= 0;
			guest_reset <= 0;
		end else begin
			guest_reset <= 0;
			if (irq) begin
				pending_irq_reg <= {1'b1, 4'b0, irq_level, irq_vector};
			end

			case (state)
			ST_CLEAR: begin
				if (clear_index == 63) begin
					clear_index <= 0;
					state <= ST_FETCH;
				end else begin
					clear_index <= clear_index + 1'b1;
				end
			end

			ST_FETCH: begin
				state <= ST_READ_A;
			end

			ST_READ_A: begin
				uir <= memory_read_data;
				state <= ST_READ_B;
			end

			ST_READ_B: begin
				operand_a <= arg1 == 0 ? exec_pc : host_read_data;
				state <= ST_READ_D;
			end

			ST_READ_D: begin
				operand_b <= is_const4 ? {12'b0, const4} :
					(arg2 == 0 ? exec_pc : host_read_data);
				state <= ST_PRE_EXEC;
			end

			ST_PRE_EXEC: begin
				state <= ST_EXEC;
			end

			ST_EXEC: begin
				if (!op[0]) begin
					case (kind)
					INST_LDRL,
					INST_STRL,
					INST_LDR,
					INST_STR: begin
						guest_req <= 1;
						guest_write <= kind == INST_STRL || kind == INST_STR;
						guest_byte <= kind == INST_LDRL || kind == INST_STRL;
						guest_bank <= 0;
						guest_address <= arithmetic_result[15:0];
						guest_wdata <= operand_dest;
						state <= ST_MEM;
					end
					INST_SETL: begin
						if (dest == 0) begin
							upc <= {next_pc[15:8], immediate8};
						end else begin
							upc <= next_pc;
						end
						state <= ST_FETCH;
					end
					INST_SETH: begin
						if (dest == 0) begin
							upc <= {immediate8, next_pc[7:0]};
						end else begin
							upc <= next_pc;
						end
						state <= ST_FETCH;
					end
					INST_MOVL: begin
						if (dest == 0) begin
							upc <= {next_pc[15:8], operand_a[7:0]};
						end else begin
							upc <= next_pc;
						end
						state <= ST_FETCH;
					end
					INST_MOVH: begin
						if (dest == 0) begin
							upc <= {operand_a[7:0], next_pc[7:0]};
						end else begin
							upc <= next_pc;
						end
						state <= ST_FETCH;
					end
					INST_MOV: begin
						upc <= dest == 0 ? operand_a : next_pc;
						state <= ST_FETCH;
					end
					INST_GGET,
					INST_GGETR: begin
						upc <= dest == 0 ? context_read_value : next_pc;
						state <= ST_FETCH;
					end
					INST_GSET,
					INST_GSETR: begin
						case (context_access_index)
						CTX_R0: guest_r0_mirror <= operand_dest;
						CTX_PC: guest_pc_mirror <= operand_dest;
						CTX_PSW: guest_psw_mirror <= operand_dest;
						CTX_IR: guest_ir_mirror <= operand_dest;
						CTX_CAUSE: cause_reg <= operand_dest;
						CTX_PENDING: pending_irq_reg <= operand_dest;
						CTX_CONTROL: begin
							if (operand_dest[0]) begin
								guest_reset <= 1;
								pending_irq_reg <= 0;
							end
						end
						default: begin end
						endcase
						upc <= next_pc;
						state <= ST_FETCH;
					end
					INST_GETF: begin
						upc <= dest == 0 ? {12'b0, alu_flags} : next_pc;
						state <= ST_FETCH;
					end
					INST_B: begin
						upc <= next_pc;
						state <= ST_FETCH;
					end
					default: begin
						upc <= next_pc;
						state <= ST_FETCH;
					end
					endcase
				end else if (kind == ALU_SHL || kind == ALU_SHR) begin
					if (initial_shift_count == 0) begin
						alu_flags <= {
							operand_a[15], operand_a == 0, 1'b0, 1'b0
						};
						upc <= dest == 0 ? operand_a : next_pc;
						state <= ST_FETCH;
					end else begin
						shift_count <= initial_shift_count;
						state <= ST_SHIFT;
					end
				end else begin
					if (kind != ALU_CMP && kind != ALU_BIT) begin
						alu_flags <= alu_next_flags;
					end
					if (kind == ALU_CMP || kind == ALU_BIT) begin
						upc <= next_pc;
					end else begin
						upc <= dest == 0 ? alu_result[15:0] : next_pc;
					end
					state <= ST_FETCH;
				end
			end

			ST_SHIFT: begin
				if (shift_count == 1) begin
					alu_flags <= {
						shifted_value[15], shifted_value == 0,
						1'b0, shift_carry
					};
					upc <= dest == 0 ? shifted_value : next_pc;
					shift_count <= 0;
					state <= ST_FETCH;
				end else begin
					operand_a <= shifted_value;
					shift_count <= shift_count - 1'b1;
				end
			end

			ST_MEM: begin
				// Neither uIR nor uPC changes while waiting, so the instruction
				// fields and next_pc need no duplicate transaction registers.
				if (guest_ready) begin
					guest_req <= 0;
					if (guest_error) begin
						cause_reg <= 16'h0001;
						upc <= BUS_ERROR_PC;
					end else if (kind == INST_LDRL || kind == INST_LDR) begin
						if (dest == 0) begin
							if (kind == INST_LDRL) begin
								upc <= {next_pc[15:8], guest_rdata[7:0]};
							end else begin
								upc <= guest_rdata;
							end
						end else begin
							upc <= next_pc;
						end
					end else begin
						upc <= next_pc;
					end
					state <= ST_FETCH;
				end
			end

			default: begin
				state <= ST_CLEAR;
				clear_index <= 0;
				guest_req <= 0;
			end
			endcase
		end
	end

endmodule

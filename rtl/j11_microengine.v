`timescale 1ns/1ps

module j11_microengine #(
	parameter integer UROM_WORDS = 1024,
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

	output wire [15:0] debug_upc,
	output wire [15:0] debug_guest_r0,
	output wire [15:0] debug_guest_pc,
	output wire [15:0] debug_guest_psw,
	output wire [15:0] debug_guest_ir,
	output wire [15:0] debug_cause,
	output wire [15:0] debug_pending_irq
);

	localparam [3:0] CTX_R0      = 4'd0;
	localparam [3:0] CTX_PC      = 4'd7;
	localparam [3:0] CTX_PSW     = 4'd8;
	localparam [3:0] CTX_IR      = 4'd9;
	localparam [3:0] CTX_CAUSE   = 4'd10;
	localparam [3:0] CTX_PENDING = 4'd11;

	localparam [1:0] ST_FETCH = 2'd0;
	localparam [1:0] ST_EXEC  = 2'd1;
	localparam [1:0] ST_MEM   = 2'd2;

	localparam [3:0] INST_LDRL = 4'h0;
	localparam [3:0] INST_STRL = 4'h1;
	localparam [3:0] INST_LDR  = 4'h2;
	localparam [3:0] INST_STR  = 4'h3;
	localparam [3:0] INST_SETL = 4'h4;
	localparam [3:0] INST_SETH = 4'h5;
	localparam [3:0] INST_MOVL = 4'h6;
	localparam [3:0] INST_MOVH = 4'h7;
	localparam [3:0] INST_MOV  = 4'h8;
	localparam [3:0] INST_GGET = 4'h9;
	localparam [3:0] INST_GSET = 4'ha;
	localparam [3:0] INST_B    = 4'hb;
	localparam [3:0] INST_GGETR = 4'hc;
	localparam [3:0] INST_GSETR = 4'hd;
	localparam [3:0] INST_GETF = 4'he;

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

	reg [15:0] urom [0:UROM_WORDS-1];
	reg [15:0] uir;
	reg [15:0] r [0:7];
	reg [15:0] jctx [0:15];
	reg [3:0] alu_flags;
	reg [1:0] state;

	reg [3:0] mem_kind;
	reg [2:0] mem_dest;
	reg [15:0] mem_next_pc;

	wire [4:0] op = uir[7:3];
	wire [2:0] dest = uir[2:0];
	wire [3:0] kind = op[4:1];
	wire [2:0] arg1 = uir[15:13];
	wire [2:0] arg2 = uir[12:10];
	wire [3:0] const4 = uir[12:9];
	wire is_const4 = uir[8];
	wire [7:0] immediate8 = uir[15:8];
	wire [3:0] context_index = uir[11:8];
	wire [15:0] exec_pc = r[0] + 1'b1;
	wire [15:0] next_pc = r[0] + 2'd2;
	localparam integer UROM_ADDR_WIDTH = $clog2(UROM_WORDS);
	wire [UROM_ADDR_WIDTH-1:0] urom_address =
		r[0][UROM_ADDR_WIDTH:1];

	reg [16:0] alu_result;
	reg [8:0] alu_byte_result;
	wire [15:0] alu_lhs = read_reg(arg1, exec_pc);
	wire [15:0] alu_rhs = is_const4 ? {12'b0, const4} : read_reg(arg2, exec_pc);
	wire [3:0] dynamic_context_index = read_reg(arg1, exec_pc);
	wire flag_z = alu_result[15:0] == 0;
	wire flag_c = alu_result[16];
	wire flag_n = alu_result[15];
	wire flag_v_sub = ((alu_lhs ^ alu_rhs) &
		(alu_lhs ^ alu_result[15:0]) & 16'h8000) != 0;
	wire flag_v_add = ((~(alu_lhs ^ alu_rhs)) &
		(alu_lhs ^ alu_result[15:0]) & 16'h8000) != 0;
	wire flag_byte_v_sub = (alu_lhs[7] ^ alu_rhs[7]) &&
		(alu_lhs[7] ^ alu_byte_result[7]);
	reg [3:0] alu_next_flags;

	integer i;
	initial begin
		for (i = 0; i < UROM_WORDS; i = i + 1) begin
			urom[i] = 16'h00b0;
		end
		if (UCODE_FILE != "") begin
			$readmemh(UCODE_FILE, urom);
		end
	end

	function [15:0] read_reg;
		input [2:0] index;
		input [15:0] current_exec_pc;
		begin
			read_reg = index == 0 ? current_exec_pc : r[index];
		end
	endfunction

	function [15:0] read_context;
		input [3:0] index;
		begin
			read_context = jctx[index];
		end
	endfunction

	function compare_true;
		input [2:0] condition;
		begin
			case (condition)
			CMP_EQ:  compare_true = flag_z;
			CMP_NE:  compare_true = !flag_z;
			CMP_MI:  compare_true = flag_n;
			CMP_VS:  compare_true = flag_v_sub;
			CMP_LT:  compare_true = flag_n ^ flag_v_sub;
			CMP_GE:  compare_true = !(flag_n ^ flag_v_sub);
			CMP_LTU: compare_true = flag_c;
			CMP_GEU: compare_true = !flag_c;
			default: compare_true = 0;
			endcase
		end
	endfunction

	always @* begin
		alu_byte_result = 0;
		case (kind)
		ALU_SEXT: alu_result = {1'b0, {8{alu_lhs[7]}}, alu_lhs[7:0]};
		ALU_SUBB: begin
			alu_byte_result = {1'b0, alu_lhs[7:0]} -
				{1'b0, alu_rhs[7:0]};
			alu_result = {9'b0, alu_byte_result[7:0]};
		end
		ALU_ADD:  alu_result = {1'b0, alu_lhs} + {1'b0, alu_rhs};
		ALU_CMP,
		ALU_SUB:  alu_result = {1'b0, alu_lhs} - {1'b0, alu_rhs};
		ALU_SHL:  alu_result = {1'b0, alu_lhs} << alu_rhs;
		ALU_SHR:  alu_result = {1'b0, alu_lhs} >> alu_rhs;
		ALU_BIT,
		ALU_AND:  alu_result = {1'b0, alu_lhs & alu_rhs};
		ALU_OR:   alu_result = {1'b0, alu_lhs | alu_rhs};
		ALU_INV:  alu_result = {1'b0, ~alu_lhs};
		ALU_XOR:  alu_result = {1'b0, alu_lhs ^ alu_rhs};
		default:  alu_result = 0;
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

	assign debug_upc = r[0];
	assign debug_guest_r0 = jctx[CTX_R0];
	assign debug_guest_pc = jctx[CTX_PC];
	assign debug_guest_psw = jctx[CTX_PSW];
	assign debug_guest_ir = jctx[CTX_IR];
	assign debug_cause = jctx[CTX_CAUSE];
	assign debug_pending_irq = jctx[CTX_PENDING];

	always @(posedge clk) begin
		if (rst) begin
			uir <= 0;
			state <= ST_FETCH;
			guest_req <= 0;
			guest_write <= 0;
			guest_byte <= 0;
			guest_bank <= 0;
			guest_address <= 0;
			guest_wdata <= 0;
			mem_kind <= 0;
			mem_dest <= 0;
			mem_next_pc <= 0;
			alu_flags <= 0;
			for (i = 0; i < 8; i = i + 1) begin
				r[i] <= 0;
			end
			for (i = 0; i < 16; i = i + 1) begin
				jctx[i] <= 0;
			end
		end else begin
			if (irq) begin
				jctx[CTX_PENDING] <= {1'b1, 4'b0, irq_level, irq_vector};
			end

			case (state)
			ST_FETCH: begin
				uir <= urom[urom_address];
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
						guest_address <= read_reg(arg1, exec_pc) + alu_rhs;
						guest_wdata <= read_reg(dest, exec_pc);
						mem_kind <= kind;
						mem_dest <= dest;
						mem_next_pc <= next_pc;
						state <= ST_MEM;
					end
					INST_SETL: begin
						if (dest == 0) begin
							r[0] <= {next_pc[15:8], immediate8};
						end else begin
							r[dest][7:0] <= immediate8;
							r[0] <= next_pc;
						end
						state <= ST_FETCH;
					end
					INST_SETH: begin
						if (dest == 0) begin
							r[0] <= {immediate8, next_pc[7:0]};
						end else begin
							r[dest][15:8] <= immediate8;
							r[0] <= next_pc;
						end
						state <= ST_FETCH;
					end
					INST_MOVL: begin
						if (dest == 0) begin
							r[0] <= {next_pc[15:8], alu_lhs[7:0]};
						end else begin
							r[dest][7:0] <= alu_lhs[7:0];
							r[0] <= next_pc;
						end
						state <= ST_FETCH;
					end
					INST_MOVH: begin
						if (dest == 0) begin
							r[0] <= {alu_lhs[7:0], next_pc[7:0]};
						end else begin
							r[dest][15:8] <= alu_lhs[7:0];
							r[0] <= next_pc;
						end
						state <= ST_FETCH;
					end
					INST_MOV: begin
						if (dest == 0) begin
							r[0] <= read_reg(arg1, exec_pc);
						end else begin
							r[dest] <= read_reg(arg1, exec_pc);
							r[0] <= next_pc;
						end
						state <= ST_FETCH;
					end
					INST_GGET: begin
						if (dest == 0) begin
							r[0] <= read_context(context_index);
						end else begin
							r[dest] <= read_context(context_index);
							r[0] <= next_pc;
						end
						state <= ST_FETCH;
					end
					INST_GSET: begin
						jctx[context_index] <= read_reg(dest, exec_pc);
						r[0] <= next_pc;
						state <= ST_FETCH;
					end
					INST_GGETR: begin
						if (dest == 0) begin
							r[0] <= read_context(dynamic_context_index);
						end else begin
							r[dest] <= read_context(dynamic_context_index);
							r[0] <= next_pc;
						end
						state <= ST_FETCH;
					end
					INST_GSETR: begin
						jctx[dynamic_context_index] <= read_reg(dest, exec_pc);
						r[0] <= next_pc;
						state <= ST_FETCH;
					end
					INST_GETF: begin
						if (dest == 0) begin
							r[0] <= {12'b0, alu_flags};
						end else begin
							r[dest] <= {12'b0, alu_flags};
							r[0] <= next_pc;
						end
						state <= ST_FETCH;
					end
					INST_B: begin
						r[0] <= r[0] +
							{{4{dest[2]}}, dest, immediate8, 1'b0};
						state <= ST_FETCH;
					end
					default: begin
						r[0] <= next_pc;
						state <= ST_FETCH;
					end
					endcase
				end else begin
					if (kind != ALU_CMP && kind != ALU_BIT) begin
						alu_flags <= alu_next_flags;
					end
					if (kind == ALU_CMP || kind == ALU_BIT) begin
						r[0] <= compare_true(dest) ? r[0] + 3'd4 : next_pc;
					end else if (dest == 0) begin
						r[0] <= alu_result[15:0];
					end else begin
						r[dest] <= alu_result[15:0];
						r[0] <= next_pc;
					end
					state <= ST_FETCH;
				end
			end

			ST_MEM: begin
				if (guest_ready) begin
					guest_req <= 0;
					if (guest_error) begin
						jctx[CTX_CAUSE] <= 16'h0001;
						r[0] <= BUS_ERROR_PC;
					end else if (
							(mem_kind == INST_LDRL || mem_kind == INST_LDR)) begin
						if (mem_dest == 0) begin
							if (mem_kind == INST_LDRL) begin
								r[0] <= {mem_next_pc[15:8], guest_rdata[7:0]};
							end else begin
								r[0] <= guest_rdata;
							end
						end else begin
							if (mem_kind == INST_LDRL) begin
								r[mem_dest][7:0] <= guest_rdata[7:0];
							end else begin
								r[mem_dest] <= guest_rdata;
							end
							r[0] <= mem_next_pc;
						end
					end else begin
						r[0] <= mem_next_pc;
					end
					state <= ST_FETCH;
				end
			end

			default: begin
				state <= ST_FETCH;
				guest_req <= 0;
			end
			endcase
		end
	end

endmodule

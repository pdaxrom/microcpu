module cpu (
	input  wire        clk,
	input  wire        rst,
	output wire        read,
	output wire [15:0] address,
	output wire [7:0]  dout,
	input  wire [7:0]  din,
	input  wire        intr
);

	// Non-ALU operations.
	localparam Inst_LDRL = 4'b0000;
	localparam Inst_STRL = 4'b0001;
	localparam Inst_LDR  = 4'b0010;
	localparam Inst_STR  = 4'b0011;
	localparam Inst_SETL = 4'b0100;
	localparam Inst_SETH = 4'b0101;
	localparam Inst_MOVL = 4'b0110;
	localparam Inst_MOVH = 4'b0111;
	localparam Inst_MOV  = 4'b1000;
	localparam Inst_SWS  = 4'b1001;
	localparam Inst_SWU  = 4'b1010;
	localparam Inst_B    = 4'b1011;
	localparam Inst_SETP = 4'b1100;
	localparam Inst_GETP = 4'b1101;

	// ALU operations.
	localparam Inst_CMP  = 4'b0000;
	localparam Inst_BIT  = 4'b0001;
	localparam Inst_SEXT = 4'b0100;
	localparam Inst_ADD  = 4'b1000;
	localparam Inst_SUB  = 4'b1001;
	localparam Inst_SHL  = 4'b1010;
	localparam Inst_SHR  = 4'b1011;
	localparam Inst_AND  = 4'b1100;
	localparam Inst_OR   = 4'b1101;
	localparam Inst_INV  = 4'b1110;
	localparam Inst_XOR  = 4'b1111;

	localparam Inst_CMP_EQ  = 3'b000;
	localparam Inst_CMP_NE  = 3'b001;
	localparam Inst_CMP_MI  = 3'b010;
	localparam Inst_CMP_VS  = 3'b011;
	localparam Inst_CMP_LT  = 3'b100;
	localparam Inst_CMP_GE  = 3'b101;
	localparam Inst_CMP_LTU = 3'b110;
	localparam Inst_CMP_GEU = 3'b111;

	localparam ST_FETCH_OP  = 4'd0;
	localparam ST_FETCH_ARG = 4'd1;
	localparam ST_READ_A    = 4'd2;
	localparam ST_READ_B    = 4'd3;
	localparam ST_READ_D    = 4'd4;
	localparam ST_EXEC      = 4'd5;
	localparam ST_MEM_LOW   = 4'd6;
	localparam ST_MEM_HIGH  = 4'd7;
	localparam ST_SKIP      = 4'd8;

	reg [3:0] state;
	reg [4:0] op;
	reg [2:0] dest;
	reg [7:0] arg_byte;

	reg [15:0] pc;
	reg [15:0] r [0:7]
		/* synthesis syn_ramstyle = "distributed" */;
	reg [15:0] arg_pc;
	reg [15:0] operand_a;
	reg [15:0] operand_b;
	reg [15:0] operand_d;
	reg [15:0] addrtmp;
	reg [15:0] store_data;
	reg [7:0] mem_low;
	reg [4:0] shift_count;

	reg super_mode_req;
	reg super_mode;
	reg [15:0] user_pc;

	wire [3:0] kind = op[4:1];
	wire instruction_is_alu = op[0];
	wire instruction_is_memory = !op[4] && !op[3] && !op[0];
	wire alu_is_shift = op[4:2] == 3'b101;
	wire mem_is_store = op[1];
	wire mem_is_word = op[2];
	wire mem_active = state == ST_MEM_LOW || state == ST_MEM_HIGH;
	wire arg_is_constant = arg_byte[0];
	wire [15:0] arg_constant = {12'b0, arg_byte[4:1]};
	wire [15:0] branch_offset =
		{{4{dest[2]}}, dest, arg_byte, 1'b0};
	wire take_interrupt = state == ST_FETCH_OP && !super_mode &&
		(super_mode_req || intr);

	assign address = mem_active ? addrtmp : pc;
	assign read = !(mem_active && mem_is_store);
	assign dout = state == ST_MEM_HIGH ? store_data[15:8] :
		store_data[7:0];

	// The register bank has one shared asynchronous read port. PC stays separate
	// so instruction fetch does not add a second read port to the bank.
	reg [2:0] rf_read_address;
	always @* begin
		case (state)
		ST_READ_A:   rf_read_address = arg_byte[7:5];
		ST_READ_B:   rf_read_address = arg_byte[4:2];
		ST_READ_D:   rf_read_address = dest;
		ST_MEM_LOW:  rf_read_address = dest;
		default:     rf_read_address = 0;
		endcase
	end

	wire operand_read_cycle = state == ST_READ_A ||
		state == ST_READ_B || state == ST_READ_D;
	wire [15:0] rf_read_data = rf_read_address == 0 ?
		(operand_read_cycle ? arg_pc : pc) : r[rf_read_address];

	// All addition and subtraction, including PC and memory-address updates,
	// share one 17-bit carry chain.
	reg [15:0] arithmetic_a;
	reg [15:0] arithmetic_b;
	reg arithmetic_subtract;
	always @* begin
		arithmetic_a = 0;
		arithmetic_b = 0;
		arithmetic_subtract = 0;
		case (state)
		ST_FETCH_OP: begin
			arithmetic_a = pc;
			arithmetic_b = 1;
		end
		ST_FETCH_ARG: begin
			arithmetic_a = pc;
			arithmetic_b = 1;
		end
		ST_EXEC: begin
			if (!instruction_is_alu && kind == Inst_B) begin
				arithmetic_a = {arg_pc[15:1], 1'b0};
				arithmetic_b = branch_offset;
			end else begin
				arithmetic_a = operand_a;
				arithmetic_b = operand_b;
				arithmetic_subtract = instruction_is_alu &&
					(kind == Inst_CMP || kind == Inst_SUB);
			end
		end
		ST_MEM_LOW: begin
			arithmetic_a = addrtmp;
			arithmetic_b = 1;
		end
		ST_SKIP: begin
			arithmetic_a = pc;
			arithmetic_b = 2;
		end
		default: begin
			arithmetic_a = 0;
			arithmetic_b = 0;
		end
		endcase
	end

	wire [16:0] arithmetic_result =
		{arithmetic_subtract, arithmetic_a} +
		{1'b0, arithmetic_b ^ {16{arithmetic_subtract}}} +
		arithmetic_subtract;

	reg [16:0] alu_result;
	always @* begin
		case (kind)
		Inst_SEXT: alu_result = {1'b0, {8{operand_a[7]}}, operand_a[7:0]};
		Inst_ADD,
		Inst_CMP,
		Inst_SUB:  alu_result = arithmetic_result;
		Inst_SHL:  alu_result = {1'b0, operand_a[14:0], 1'b0};
		Inst_SHR:  alu_result = {2'b00, operand_a[15:1]};
		Inst_BIT,
		Inst_AND:  alu_result = {1'b0, operand_a & operand_b};
		Inst_OR:   alu_result = {1'b0, operand_a | operand_b};
		Inst_INV:  alu_result = {1'b0, ~operand_a};
		Inst_XOR:  alu_result = {1'b0, operand_a ^ operand_b};
		default:   alu_result = {1'b0, operand_a};
		endcase
	end

	wire flag_z = alu_result[15:0] == 0;
	wire flag_c = alu_result[16];
	wire flag_n = alu_result[15];
	wire flag_v = ((operand_a ^ operand_b) &
		(operand_a ^ alu_result[15:0]) & 16'h8000) != 0;

	reg compare_true;
	always @* begin
		case (dest)
		Inst_CMP_EQ:  compare_true = flag_z;
		Inst_CMP_NE:  compare_true = !flag_z;
		Inst_CMP_MI:  compare_true = flag_n;
		Inst_CMP_VS:  compare_true = flag_v;
		Inst_CMP_LT:  compare_true = flag_n ^ flag_v;
		Inst_CMP_GE:  compare_true = !(flag_n ^ flag_v);
		Inst_CMP_LTU: compare_true = flag_c;
		Inst_CMP_GEU: compare_true = !flag_c;
		default:      compare_true = 0;
		endcase
	end

	// A single centralized write port keeps register-write decoding shared.
	reg rf_write_enable;
	reg [2:0] rf_write_address;
	reg [15:0] rf_write_data;
	always @* begin
		rf_write_enable = 0;
		rf_write_address = 0;
		rf_write_data = 0;
		case (state)
		ST_FETCH_OP: begin
			rf_write_enable = 1;
			rf_write_data = take_interrupt ? 16'h0002 :
				arithmetic_result[15:0];
		end
		ST_FETCH_ARG: begin
			rf_write_enable = 1;
			rf_write_data = arithmetic_result[15:0];
		end
		ST_EXEC: begin
			if (instruction_is_alu) begin
				if (kind != Inst_CMP && kind != Inst_BIT &&
					(!alu_is_shift || shift_count <= 1)) begin
					rf_write_enable = 1;
					rf_write_address = dest;
					rf_write_data = shift_count == 0 && alu_is_shift ?
						operand_a : alu_result[15:0];
				end
			end else begin
				case (kind)
				Inst_SWU: begin
					rf_write_enable = 1;
					rf_write_data = user_pc;
				end
				Inst_B: begin
					rf_write_enable = 1;
					rf_write_data = arithmetic_result[15:0];
				end
				Inst_SETL,
				Inst_MOVL: begin
					rf_write_enable = 1;
					rf_write_address = dest;
					rf_write_data = {operand_d[15:8],
						op[2] ? operand_a[7:0] : arg_byte};
				end
				Inst_SETH,
				Inst_MOVH: begin
					rf_write_enable = 1;
					rf_write_address = dest;
					rf_write_data = {op[2] ? operand_a[7:0] : arg_byte,
						operand_d[7:0]};
				end
				Inst_MOV,
				Inst_GETP: begin
					rf_write_enable = 1;
					rf_write_address = dest;
					rf_write_data = op[1] ? user_pc : operand_a;
				end
				default: begin
					rf_write_enable = 0;
				end
				endcase
			end
		end
		ST_MEM_LOW: begin
			if (!mem_is_store && !mem_is_word) begin
				rf_write_enable = 1;
				rf_write_address = dest;
				rf_write_data = {rf_read_data[15:8], din};
			end
		end
		ST_MEM_HIGH: begin
			if (!mem_is_store) begin
				rf_write_enable = 1;
				rf_write_address = dest;
				rf_write_data = {din, mem_low};
			end
		end
		ST_SKIP: begin
			rf_write_enable = 1;
			rf_write_data = arithmetic_result[15:0];
		end
		default: begin
			rf_write_enable = 0;
		end
		endcase
	end

	always @(negedge clk) begin
		if (rst) begin
			pc <= 0;
		end else if (rf_write_enable) begin
			if (rf_write_address == 0) begin
				pc <= rf_write_data;
			end else begin
				r[rf_write_address] <= rf_write_data;
			end
		end
	end

	always @(negedge clk) begin
		if (rst) begin
			state <= ST_FETCH_OP;
			op <= 0;
			dest <= 0;
			arg_byte <= 0;
			arg_pc <= 0;
			operand_a <= 0;
			operand_b <= 0;
			operand_d <= 0;
			addrtmp <= 0;
			store_data <= 0;
			mem_low <= 0;
			shift_count <= 0;
			super_mode_req <= 0;
			super_mode <= 0;
			user_pc <= 0;
		end else begin
			case (state)
			ST_FETCH_OP: begin
				if (take_interrupt) begin
					user_pc <= pc;
					super_mode <= 1;
				end else begin
					{op, dest} <= din;
					state <= ST_FETCH_ARG;
				end
			end
			ST_FETCH_ARG: begin
				arg_byte <= din;
				arg_pc <= pc;
				if (instruction_is_alu || instruction_is_memory ||
					kind == Inst_MOVL || kind == Inst_MOVH ||
					kind == Inst_MOV) begin
					state <= ST_READ_A;
				end else if (kind == Inst_SETL || kind == Inst_SETH ||
					kind == Inst_SETP) begin
					state <= ST_READ_D;
				end else begin
					state <= ST_EXEC;
				end
			end
			ST_READ_A: begin
				operand_a <= rf_read_data;
				if (instruction_is_alu || instruction_is_memory) begin
					state <= ST_READ_B;
				end else if (kind == Inst_MOVL || kind == Inst_MOVH) begin
					state <= ST_READ_D;
				end else begin
					state <= ST_EXEC;
				end
			end
			ST_READ_B: begin
				operand_b <= arg_is_constant ? arg_constant : rf_read_data;
				if (arg_is_constant) begin
					shift_count <= {1'b0, arg_byte[4:1]};
				end else begin
					shift_count <= |rf_read_data[15:4] ? 5'd16 :
						{1'b0, rf_read_data[3:0]};
				end
				if (instruction_is_memory && mem_is_store) begin
					state <= ST_READ_D;
				end else begin
					state <= ST_EXEC;
				end
			end
			ST_READ_D: begin
				operand_d <= rf_read_data;
				state <= ST_EXEC;
			end
			ST_EXEC: begin
				if (instruction_is_memory) begin
					addrtmp <= arithmetic_result[15:0];
					store_data <= operand_d;
					state <= ST_MEM_LOW;
				end else if (instruction_is_alu) begin
					if (alu_is_shift && shift_count > 1) begin
						operand_a <= alu_result[15:0];
						shift_count <= shift_count - 1'b1;
					end else if ((kind == Inst_CMP || kind == Inst_BIT) &&
						compare_true) begin
						state <= ST_SKIP;
					end else begin
						state <= ST_FETCH_OP;
					end
				end else begin
					if (kind == Inst_SETP) begin
						user_pc <= operand_d;
					end else if (kind == Inst_SWS) begin
						super_mode_req <= 1;
					end else if (kind == Inst_SWU) begin
						super_mode <= 0;
						super_mode_req <= 0;
					end
					state <= ST_FETCH_OP;
				end
			end
			ST_MEM_LOW: begin
				if (mem_is_word) begin
					if (!mem_is_store) mem_low <= din;
					addrtmp <= arithmetic_result[15:0];
					state <= ST_MEM_HIGH;
				end else begin
					state <= ST_FETCH_OP;
				end
			end
			ST_MEM_HIGH: begin
				state <= ST_FETCH_OP;
			end
			ST_SKIP: begin
				state <= ST_FETCH_OP;
			end
			default: begin
				state <= ST_FETCH_OP;
			end
			endcase
		end
	end
endmodule

module cpu (
    input  wire clk,           // clock
    input  wire rst,           // reset
    output reg  read,          // CPU read request
    output wire [15:0] address, // read/write address
    output reg  [7:0] dout,    // write data
    input  wire [7:0] din,     // read data
	input wire intr
);

	// NO ALU OPS
	localparam Inst_LDRL  = 4'b0000; // dest, op1, offset  : RL[dest] = M[R[op1] + offset]
	localparam Inst_STRL  = 4'b0001; // src,  op1, offset  : M[R[op1] + offset] = RL[src]
	localparam Inst_LDR   = 4'b0010; // dest, op1, offset  : R[dest]  = M[R[op1] + offset]
	localparam Inst_STR   = 4'b0011; // src,  op1, offset  : M[R[op1] + offset] = R[src]
	localparam Inst_SETL  = 4'b0100; // dest, const        : RL[dest] = const
	localparam Inst_SETH  = 4'b0101; // dest, const        : RH[dest] = const
	localparam Inst_MOVL  = 4'b0110; // dest, src          : RL[dest] = RL[src]
	localparam Inst_MOVH  = 4'b0111; // dest, src          : RH[dest] = RL[src]
	
	localparam Inst_MOV   = 4'b1000; // dest, src          : R[dest] = R[src]

	localparam Inst_SWS   = 4'b1001;
	localparam Inst_SWU   = 4'b1010;

	localparam Inst_B     = 4'b1011; // const              : R[0] = R[0] + const
	
	// ALU OPS
	
	localparam Inst_CMP   = 4'b0000; // op1, op2			 :
	localparam Inst_BIT   = 4'b0001; // op1, op2
	localparam Inst_SEXT  = 4'b0100; // op1, op2			 : R[dest] = (signed) R[op1][7:0]

	localparam Inst_ADD   = 4'b1000; // dest, op1, op2     : R[dest] = R[op1] + R[op2]
	localparam Inst_SUB   = 4'b1001; // dest, op1, op2     : R[dest] = R[op1] - R[op2]
	localparam Inst_SHL   = 4'b1010; // dest, op1, op2     : R[dest] = R[op1] << R[op2]
	localparam Inst_SHR   = 4'b1011; // dest, op1, op2     : R[dest] = R[op1] >> R[op2]
	localparam Inst_AND   = 4'b1100; // dest, op1, op2     : R[dest] = R[op1] & R[op2]
	localparam Inst_OR    = 4'b1101; // dest, op1, op2     : R[dest] = R[op1] | R[op2]
	localparam Inst_INV   = 4'b1110; // dest, op1          : R[dest] = ~R[op1]
	localparam Inst_XOR   = 4'b1111; // dest, op1, op2     : R[dest] = R[op1] ^ R[op2]

	// CMP RISC EXT
	localparam Inst_CMP_EQ  = 3'b000; // Z = 1
	localparam Inst_CMP_NE  = 3'b001; // Z = 0
	localparam Inst_CMP_MI  = 3'b010; // N = 1
	localparam Inst_CMP_VS  = 3'b011; // V = 1
	localparam Inst_CMP_LT  = 3'b100;
	localparam Inst_CMP_GE  = 3'b101;
	localparam Inst_CMP_LTU = 3'b110;
	localparam Inst_CMP_GEU = 3'b111;

	reg  [4:0] op;        // opcode
	reg  [2:0] dest;      // destination arg

	reg  [15:0] r[0:7];   // registers
	reg  [15:0] addrtmp;  // data address
	reg	 [16:0] aluacc;   // ALU accumulator
	reg  [15:0] aluval1;
	reg  [15:0] aluval2;

	reg [1:0] memio;	   // memory io operation
	reg [1:0] aluop;	   // ALU operation in progress;

	assign address = memio ? addrtmp : r[0];
	wire [2:0] arg1 = din[7:5];
	wire [2:0] arg2 = din[4:2];
	wire [3:0] const4 = din[4:1];
	wire is_const4 = din[0]; // use constant
	
	wire [ 7:0] constant = din[7:0];
	wire [15:0] val1 = r[arg1];
	wire [15:0] val2u = is_const4 ? {12'b000000000000, const4} : r[arg2];

	wire flag_Z = aluacc[15:0] == 0;
	wire flag_C = aluacc[16];
	wire flag_N = aluacc[15];
	wire flag_V = ((aluval1 ^ aluval2) & (aluval1 ^ aluacc[15:0]) & 16'h8000) != 0;

	reg super_mode_req;
	reg super_mode;
	reg [15:0] user_pc;

	always @(negedge clk) begin
		if (rst) begin
			op <= 0;
			dest <= 0;
		end else if ((aluop | memio) == 0) begin
			if (~r[0][0]) begin
				//op <= din[7:3];
				//dest <= din[2:0];
				{op, dest} <= din;
			end
		end
	end
	
	always @(negedge clk) begin
		if (rst) begin
			r[0] <= 0;
			super_mode <= 0;
			super_mode_req <= 0;
			user_pc <= 0;
		end else if (aluop) begin
				if (aluop == 2'b10) begin
					if (op[4:1] == Inst_CMP || op[4:1] == Inst_BIT) begin
						if ((dest == Inst_CMP_EQ && flag_Z) ||
							(dest == Inst_CMP_NE && ~flag_Z) ||
							(dest == Inst_CMP_MI && flag_N) ||
							(dest == Inst_CMP_VS && flag_V) ||
							(dest == Inst_CMP_LT && (flag_N ^ flag_V)) ||
							(dest == Inst_CMP_GE && ~(flag_N ^ flag_V)) ||
							(dest == Inst_CMP_LTU && flag_C) ||
							(dest == Inst_CMP_GEU && ~flag_C)) r[0] <= r[0] + 2;
					end	else r[dest] <= aluacc[15:0];
				end
		end else if (memio) begin
					if (op[2:1] == 2'b00 || op[2:1] == 2'b10) begin
						if (memio == 2'b01) r[dest][7:0] <= din;
						else if (memio == 2'b11) r[dest][15:8] <= din;
					end
		end else begin
				r[0] <= r[0] + 1;   // increment PC by default
				if (~r[0][0] && (~super_mode && (super_mode_req || intr))) begin
					user_pc <= r[0];
					r[0] <= 16'h0002;
					super_mode <= ~super_mode;
				end
				if (r[0][0] && ~op[0]) begin
					case (op[4:1])
						Inst_SETL,
						Inst_MOVL: r[dest][ 7:0] <= op[2] ? r[arg1][7:0] : constant;
						Inst_SETH,
						Inst_MOVH: r[dest][15:8] <= op[2] ? r[arg1][7:0] : constant;
						Inst_MOV:  r[dest] <= val1;
						Inst_SWS : super_mode_req <= 1;
						Inst_SWU : begin
								r[0] <= user_pc;
								super_mode <= 0;
								super_mode_req <= 0;
							end
						Inst_B: begin
									r[0] <= {r[0][15:1], 1'b0} + 
										{dest[2], dest[2], dest[2], dest[2],
										 dest, constant, 1'b0 };

							end
					endcase
				end
		end
	end
	
	always @(negedge clk) begin
		if (rst) begin
			read <= 1;
			memio <= 0;
			addrtmp <= 0;
		end else if (memio) begin
			memio <= memio + 1;
			if (memio == 2'b01) begin
					if (op[2:1] == 2'b00 || op[2:1] == 2'b01) begin
						memio <= 0;				// read it from DIN
					end
					read <= 1;
			end else if (memio == 2'b10) begin
					addrtmp <= addrtmp + 1;
					if (op[2:1] == 2'b11) begin
						read <= ~read;
						dout <= r[dest][15:8];
					end
			end else if (memio == 2'b11) begin
				read <= 1;
			end
		end else if (op[4] == 0 && op[3] == 0 && op[0] == 0 & r[0][0]) begin
			memio <= memio + 1;					// switch address to data
			addrtmp <= r[arg1] + val2u;			// set data address
			if (op[1]) begin
				read <= ~read;                    	// request a write
				dout <= r[dest][7:0];          	// output the data
			end
		end
	end

	always @(negedge clk) begin
		if (rst) begin
			aluop <= 2'b11;
			aluval1 <= 0;
			aluval2 <= 0;
		end else if (aluop == 2'b10) begin
			aluop <= 0;
		end else if (aluop) begin
			aluop <= aluop + 1;
		end else if (op[0] & r[0][0]) begin
			aluval1 <= r[arg1];
			aluval2 <= val2u;
			aluop <= 2'b01;
		end
	end
	
	always @(negedge clk) begin
		if (rst) aluacc <= 0;
		else if (aluop == 2'b01) begin
				case (op[4:1])
					Inst_SEXT: aluacc <= {1'b0, aluval1[7], aluval1[7], aluval1[7], aluval1[7],
											aluval1[7], aluval1[7], aluval1[7], aluval1[7],
											aluval1[7:0]};
					Inst_ADD: aluacc <= {1'b0, aluval1} + {1'b0, aluval2};
					Inst_CMP,
					Inst_SUB: aluacc <= {1'b0, aluval1} - {1'b0, aluval2};
					Inst_SHL: aluacc <= {1'b0, aluval1} << {1'b0, aluval2};
					Inst_SHR: aluacc <= {1'b0, aluval1} >> {1'b0, aluval2};
					Inst_BIT,
					Inst_AND: aluacc <= {1'b0, aluval1} & {1'b0, aluval2};
					Inst_OR:  aluacc <= {1'b0, aluval1} | {1'b0, aluval2};
					Inst_INV: aluacc <= ~aluval1;
					Inst_XOR: aluacc <= {1'b0, aluval1} ^ {1'b0, aluval2};
				endcase
		end
	end
endmodule

module cpu (
    input  wire clk,           // clock
    input  wire rst,           // reset
    output reg  read,          // CPU read request
    output wire [15:0] address, // read/write address
    output reg  [7:0] dout,    // write data
    input  wire [7:0] din      // read data
	
//	output wire [4:0] d_op,
//	output wire [2:0] d_dest,
//	output wire [2:0] d_arg1,
//	output wire [4:0] d_arg2
);

	// NO ALU OPS
	localparam Inst_LDRL  = 5'b00000; // dest, op1, offset  : RL[dest] = M[R[op1] + offset]
	localparam Inst_STRL  = 5'b00010; // src,  op1, offset  : M[R[op1] + offset] = RL[src]
	localparam Inst_LDRH  = 5'b00100; // dest, op1, offset  : RH[dest] = M[R[op1] + offset]
	localparam Inst_STRH  = 5'b00110; // src,  op1, offset  : M[R[op1] + offset] = RH[src]
	localparam Inst_SETL  = 5'b01000; // dest, const        : RL[dest] = const
	localparam Inst_SETH  = 5'b01010; // dest, const        : RH[dest] = const
	localparam Inst_MOVL  = 5'b01100; // dest, src          : RL[dest] = RL[src]
	localparam Inst_MOVH  = 5'b01110; // dest, src          : RH[dest] = RL[src]
	
	localparam Inst_MOV   = 5'b10000; // dest, src          : R[dest] = R[src]
	
	localparam Inst_B     = 5'b10110; // const              : R[0] = R[0] + const
	localparam Inst_BLE   = 5'b11000; // const              : if (C || Z) R[0] = R[0] + const
	localparam Inst_BGE   = 5'b11010; // const              : if (!CR[0] = R[0] + const
	localparam Inst_BEQ   = 5'b11100; // const              : R[0] = R[0] + const
	localparam Inst_BCS   = 5'b11110; // const              : R[0] = R[0] + const
	
	// ALU OPS
	
	localparam Inst_CMP   = 5'b00001; // op1, op2
	localparam Inst_SEXT  = 5'b00011; // op1, op2			 : R[dest] = (signed) R[op1][7:0]
	
	localparam Inst_ADDC  = 5'b01001; // dest, op1, op2     : R[dest] = R[op1] + R[op2] + C
	localparam Inst_SUBC  = 5'b01011; // dest, op1, op2     : R[dest] = R[op1] - R[op2] - C
	
	localparam Inst_ADD   = 5'b10001; // dest, op1, op2     : R[dest] = R[op1] + R[op2]
	localparam Inst_SUB   = 5'b10011; // dest, op1, op2     : R[dest] = R[op1] - R[op2]
	localparam Inst_SHL   = 5'b10101; // dest, op1, op2     : R[dest] = R[op1] << R[op2]
	localparam Inst_SHR   = 5'b10111; // dest, op1, op2     : R[dest] = R[op1] >> R[op2]
	localparam Inst_AND   = 5'b11001; // dest, op1, op2     : R[dest] = R[op1] & R[op2]
	localparam Inst_OR    = 5'b11011; // dest, op1, op2     : R[dest] = R[op1] | R[op2]
	localparam Inst_INV   = 5'b11101; // dest, op1          : R[dest] = ~R[op1]
	localparam Inst_XOR   = 5'b11111; // dest, op1, op2     : R[dest] = R[op1] ^ R[op2]

	reg  [4:0] op;        // opcode
	reg  [2:0] dest;      // destination arg
	wire [2:0] arg1;      // first arg
	wire [2:0] arg2;      // second arg
	wire [3:0] const4;    // offset
	wire       is_const4; // second arg is const4

	reg  [15:0] r[0:7];   // registers
	reg  [15:0] addrtmp;  // data address
	reg	 [16:0] aluacc;   // ALU accumulator
	reg  [15:0] aluval1;
	reg  [15:0] aluval2;
	
	reg         flag_C;   // flag C
	reg		    flag_Z;   // flag Z
	reg         flag_V;   // flag V
	reg         flag_N;   // flag N
	
	wire [7:0] constant;  // constant arg
	wire [15:0] constant16;
	wire [15:0] val1;
	wire [15:0] val2;
	wire [15:0] val2u;
	
	reg memio;			   // memory io operation
	reg [1:0] aluop;	   // ALU operation in progress;

	assign address = memio ? addrtmp : r[0];
	assign arg1 = din[7:5];
	assign arg2 = din[4:2];
	assign const4 = din[4:1];
	assign is_const4 = din[0]; // use constant
	
	assign constant = din[7:0];
	assign constant16 = {constant[7], constant[7], constant[7], constant[7],
						  constant[7], constant[7], constant[7], constant[7],
						  constant};
	assign val1 = r[arg1];
	assign val2u = is_const4 ? {12'b000000000000, const4} : r[arg2];
	assign val2 = is_const4 ? {const4[3], const4[3], const4[3], const4[3],
								const4[3], const4[3], const4[3], const4[3],
								const4[3], const4[3], const4[3], const4[3],
								const4} : r[arg2];

//	assign d_op = op;
//	assign d_dest = dest;
//	assign d_arg1 = arg1;
//	assign d_arg2 = {const4, is_const4};

	always @(negedge clk) begin
		if (rst) begin
			r[0] <= 0;
			memio <= 0;
			read <= 1;
			aluop <= 3;
		end else begin
			if (aluop != 0) begin
				aluop <= aluop + 1;
				if (aluop == 2'b01) begin
					case (op)
						Inst_ADDC:aluacc <= {1'b0, aluval1} + {1'b0, aluval2} + {15'b0000000000000000, flag_C};
						Inst_SUBC:aluacc <= {1'b0, aluval1} - {1'b0, aluval2} - {15'b0000000000000000, flag_C};
						Inst_SEXT: aluacc <= {1'b0, aluval1[7], aluval1[7], aluval1[7], aluval1[7],
												aluval1[7], aluval1[7], aluval1[7], aluval1[7],
												aluval1[7:0]};
						Inst_ADD: aluacc <= {1'b0, aluval1} + {1'b0, aluval2};
						Inst_CMP,
						Inst_SUB: aluacc <= {1'b0, aluval1} - {1'b0, aluval2};
						Inst_SHL: aluacc <= {1'b0, aluval1} << {1'b0, aluval2};
						Inst_SHR: aluacc <= {1'b0, aluval1} >> {1'b0, aluval2};
						Inst_AND: aluacc <= {1'b0, aluval1} & {1'b0, aluval2};
						Inst_OR:  aluacc <= {1'b0, aluval1} | {1'b0, aluval2};
						Inst_INV: aluacc <= ~{1'b0, aluval1};
						Inst_XOR: aluacc <= {1'b0, aluval1} ^ {1'b0, aluval2};
					endcase
				end else if (aluop == 2'b10) begin
					flag_Z <= aluacc[15:0] == 0;
					flag_C <= aluacc[16];
					flag_N <= aluacc[15];

					if (op == Inst_ADD) flag_V <= ((aluval1 ^ ~aluval2) & (aluval1 ^ aluacc[15:0]) & 16'h8000) != 0;
					else if (op == Inst_CMP || op == Inst_SUB) flag_V <= ((aluval1 ^ aluval2) & (aluval1 ^ aluacc[15:0]) & 16'h8000) != 0;
					else flag_V <= 0;
					
					if (op != Inst_CMP) begin
						r[dest] <= aluacc[15:0];
					end
					
					aluop <= 0;
				end
			end else if (memio == 0) begin
				r[0] <= r[0] + 1;   // increment PC by default
				if (~r[0][0]) begin
					op <= din[7:3];
					dest <= din[2:0];
				end else begin
					aluop <= {1'b0, op[0]};
					if (op[0]) begin
						aluval1 <= r[arg1];
						aluval2 <= val2u;
					end
					// Perform the operation
					case (op)
						Inst_LDRL,
						Inst_STRL,
						Inst_LDRH,
						Inst_STRH: begin
								memio <= ~memio;							// switch address to data
								addrtmp <= r[arg1] + val2u;// set data address
								if (op == Inst_STRL) begin
									read <= ~read;                    // request a write
									dout <= r[dest][7:0];          // output the data
								end
								if (op == Inst_STRH) begin
									read <= ~read;
									dout <= r[dest][15:8];
								end
							end
						Inst_SETL: begin
								r[dest][7:0] <= constant;			// set the reg to constant
							end
						Inst_SETH: begin
								r[dest][15:8] <= constant;
							end
						Inst_MOVL: begin
								r[dest][7:0] <= r[arg1][7:0];
							end
						Inst_MOVH: begin
								r[dest][15:8] <= r[arg1][7:0];
							end
						Inst_MOV: begin
								r[dest] <= val1;
							end
						default:	
							begin
								if ((op == Inst_B) ||
									(op == Inst_BEQ && flag_Z) ||
									(op == Inst_BCS && flag_C) ||
									(op == Inst_BLE && (flag_Z |(flag_N ^ flag_V))) ||
									(op == Inst_BGE && ~(flag_N ^ flag_V))) begin
									r[0] <= r[0] + 
										{constant[7], constant[7], constant[7], constant[7],
										 constant[7], constant[7], constant[7], constant[7], constant };
								end
							end
					endcase
				end
			end else begin
				if (op == Inst_LDRL) r[dest][7:0] <= din;								// read the data
				else if (op == Inst_LDRH) r[dest][15:8] <= din;
				else read <= ~read;
				memio <= ~memio;										// switch address to programm
			end
		end
	end
endmodule
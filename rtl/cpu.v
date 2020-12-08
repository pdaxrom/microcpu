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
	localparam Inst_LDRL  = 4'b0000; // dest, op1, offset  : RL[dest] = M[R[op1] + offset]
	localparam Inst_STRL  = 4'b0001; // src,  op1, offset  : M[R[op1] + offset] = RL[src]
	localparam Inst_LDRH  = 4'b0010; // dest, op1, offset  : RH[dest] = M[R[op1] + offset]
	localparam Inst_STRH  = 4'b0011; // src,  op1, offset  : M[R[op1] + offset] = RH[src]
	localparam Inst_SETL  = 4'b0100; // dest, const        : RL[dest] = const
	localparam Inst_SETH  = 4'b0101; // dest, const        : RH[dest] = const
	localparam Inst_MOVL  = 4'b0110; // dest, src          : RL[dest] = RL[src]
	localparam Inst_MOVH  = 4'b0111; // dest, src          : RH[dest] = RL[src]
	
	localparam Inst_MOV   = 4'b1000; // dest, src          : R[dest] = R[src]
	
	localparam Inst_B     = 4'b1011; // const              : R[0] = R[0] + const
	localparam Inst_BLE   = 4'b1100; // const              : if (C || Z) R[0] = R[0] + const
	localparam Inst_BGE   = 4'b1101; // const              : if (!CR[0] = R[0] + const
	localparam Inst_BEQ   = 4'b1110; // const              : R[0] = R[0] + const
	localparam Inst_BCS   = 4'b1111; // const              : R[0] = R[0] + const
	
	// ALU OPS
	
	localparam Inst_CMP   = 4'b0000; // op1, op2			 :
	localparam Inst_SEXT  = 4'b0001; // op1, op2			 : R[dest] = (signed) R[op1][7:0]
	localparam Inst_SETS  = 4'b0010; // src				 : ICZVN = R[src]
	localparam Inst_GETS  = 4'b0011; // dst				 : R[dst] = ICZVN
	
	localparam Inst_ADDC  = 4'b0100; // dest, op1, op2     : R[dest] = R[op1] + R[op2] + C
	localparam Inst_SUBC  = 4'b0101; // dest, op1, op2     : R[dest] = R[op1] - R[op2] - C
	localparam Inst_TST   = 4'b0110; // op1, op2			 :
	
	localparam Inst_ADD   = 4'b1000; // dest, op1, op2     : R[dest] = R[op1] + R[op2]
	localparam Inst_SUB   = 4'b1001; // dest, op1, op2     : R[dest] = R[op1] - R[op2]
	localparam Inst_SHL   = 4'b1010; // dest, op1, op2     : R[dest] = R[op1] << R[op2]
	localparam Inst_SHR   = 4'b1011; // dest, op1, op2     : R[dest] = R[op1] >> R[op2]
	localparam Inst_AND   = 4'b1100; // dest, op1, op2     : R[dest] = R[op1] & R[op2]
	localparam Inst_OR    = 4'b1101; // dest, op1, op2     : R[dest] = R[op1] | R[op2]
	localparam Inst_INV   = 4'b1110; // dest, op1          : R[dest] = ~R[op1]
	localparam Inst_XOR   = 4'b1111; // dest, op1, op2     : R[dest] = R[op1] ^ R[op2]

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
	
	reg			flag_I;	   // flag I
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
			op <= 0;
		end else begin
			if (aluop) begin
				if (aluop == 2'b10) begin
					if (op[4:1] != Inst_CMP && op[4:1] != Inst_TST && op[4:1] != Inst_SETS) begin
						r[dest] <= aluacc[15:0];
					end
					op[0] <= 0;
				end
			end else if (memio == 0) begin
				r[0] <= r[0] + 1;   // increment PC by default
				if (~r[0][0]) begin
					op <= din[7:3];
					dest <= din[2:0];
				end else if (~op[0]) begin
					// Perform the operation
						case (op[4:1])
							Inst_LDRL,
							Inst_STRL,
							Inst_LDRH,
							Inst_STRH: begin
									memio <= ~memio;							// switch address to data
									addrtmp <= r[arg1] + val2u;// set data address
									if (op[4:1] == Inst_STRL) begin
										read <= ~read;                    // request a write
										dout <= r[dest][7:0];          // output the data
									end else if (op[4:1] == Inst_STRH) begin
										read <= ~read;
										dout <= r[dest][15:8];
									end
								end
							Inst_SETL: r[dest][7:0] <= constant;			// set the reg to constant
							Inst_SETH: r[dest][15:8] <= constant;
							Inst_MOVL: r[dest][7:0] <= r[arg1][7:0];
							Inst_MOVH: r[dest][15:8] <= r[arg1][7:0];
							Inst_MOV:  r[dest] <= val1;
							default: begin
									if ((op[4:1] == Inst_B) ||
										(op[4:1] == Inst_BEQ && flag_Z) ||
										(op[4:1] == Inst_BCS && flag_C) ||
										(op[4:1] == Inst_BLE && (flag_Z |(flag_N ^ flag_V))) ||
										(op[4:1] == Inst_BGE && ~(flag_N ^ flag_V))) begin
										r[0] <= r[0] + 
											{constant[7], constant[7], constant[7], constant[7],
											 constant[7], constant[7], constant[7], constant[7], constant };
									end
								end
						endcase
				end
			end else begin
				if (op[4:1] == Inst_LDRL) r[dest][7:0] <= din;								// read the data
				else if (op[4:1] == Inst_LDRH) r[dest][15:8] <= din;
				else read <= ~read;
				memio <= ~memio;										// switch address to programm
			end
		end
	end
	
	always @(negedge clk) begin
		if (rst) begin
			flag_I <= 0;
			aluop <= 2'b11;
		end else if (aluop) begin
			aluop <= aluop + 1;
			if (aluop == 2'b01) begin
				case (op[4:1])
					Inst_SEXT: aluacc <= {1'b0, aluval1[7], aluval1[7], aluval1[7], aluval1[7],
											aluval1[7], aluval1[7], aluval1[7], aluval1[7],
											aluval1[7:0]};
					Inst_SETS: {flag_I, flag_C, flag_Z, flag_V, flag_N } <= aluval1[4:0];
					Inst_GETS: aluacc <= {11'h000, flag_I, flag_C, flag_Z, flag_V, flag_N};
					Inst_ADDC,
					Inst_ADD: aluacc <= {1'b0, aluval1} + {1'b0, aluval2} + {15'b0000000000000000, op[3] & flag_C};
					Inst_CMP,
					Inst_SUBC,
					Inst_SUB: aluacc <= {1'b0, aluval1} - {1'b0, aluval2} - {15'b0000000000000000, op[3] & flag_C};
					Inst_SHL: aluacc <= {1'b0, aluval1} << {1'b0, aluval2};
					Inst_SHR: aluacc <= {1'b0, aluval1} >> {1'b0, aluval2};
					Inst_TST,
					Inst_AND: aluacc <= {1'b0, aluval1} & {1'b0, aluval2};
					Inst_OR:  aluacc <= {1'b0, aluval1} | {1'b0, aluval2};
					Inst_INV: aluacc <= ~{1'b0, aluval1};
					Inst_XOR: aluacc <= {1'b0, aluval1} ^ {1'b0, aluval2};
				endcase
			end else if (aluop == 2'b10) begin
				if (op[4:1] != Inst_SETS && op[4:1] != Inst_GETS) begin
					flag_Z <= aluacc[15:0] == 0;
					flag_C <= aluacc[16];
					flag_N <= aluacc[15];

					if (op[4:1] == Inst_ADD || op[4:1] == Inst_ADDC) flag_V <= ((aluval1 ^ ~aluval2) & (aluval1 ^ aluacc[15:0]) & 16'h8000) != 0;
					else if (op[4:1] == Inst_CMP || op[4:1] == Inst_SUB || op[4:1] == Inst_SUBC) flag_V <= ((aluval1 ^ aluval2) & (aluval1 ^ aluacc[15:0]) & 16'h8000) != 0;
					else flag_V <= 0;
				end
					
				aluop <= 2'b00;
			end
		end else if (op[0]) begin
			aluval1 <= r[arg1];
			aluval2 <= val2u;
			aluop <= 2'b01;
		end
	end
endmodule

module cpu (
    input  wire clk,           // clock
    input  wire rst,           // reset
    output reg  write,         // CPU write request
    output wire  read,          // CPU read request
    output wire [7:0] address, // read/write address
    output reg  [7:0] dout,    // write data
    input  wire [7:0] din      // read data
);

	localparam Inst_NOP   = 0;  // 0 filled
	localparam Inst_LOAD  = 1;  // dest, op1, offset  : R[dest] = M[R[op1] + offset]
	localparam Inst_STORE = 2;  // src, op1, offset   : M[R[op1] + offset] = R[src]
	localparam Inst_SET   = 3;  // dest, const        : R[dest] = const
	localparam Inst_LT    = 4;  // dest, op1, op2     : R[dest] = R[op1] < R[op2]
	localparam Inst_EQ    = 5;  // dest, op1, op2     : R[dest] = R[op1] == R[op2]
	localparam Inst_BEQ   = 6;  // op1, const         : R[0] = R[0] + (R[op1] == const ? 2 : 1)
	localparam Inst_BNEQ  = 7;  // op1, const         : R[0] = R[0] + (R[op1] != const ? 2 : 1)
	localparam Inst_ADD   = 8;  // dest, op1, op2     : R[dest] = R[op1] + R[op2]
	localparam Inst_SUB   = 9;  // dest, op1, op2     : R[dest] = R[op1] - R[op2]
	localparam Inst_SHL   = 10; // dest, op1, op2     : R[dest] = R[op1] << R[op2]
	localparam Inst_SHR   = 11; // dest, op1, op2     : R[dest] = R[op1] >> R[op2]
	localparam Inst_AND   = 12; // dest, op1, op2     : R[dest] = R[op1] & R[op2]
	localparam Inst_OR    = 13; // dest, op1, op2     : R[dest] = R[op1] | R[op2]
	localparam Inst_INV   = 14; // dest, op1          : R[dest] = ~R[op1]
	localparam Inst_XOR   = 15; // dest, op1, op2     : R[dest] = R[op1] ^ R[op2]

	reg  [3:0] op;        // opcode
	reg  [3:0] dest;      // destination arg
	wire [3:0] arg1;      // first arg
	wire [3:0] arg2;      // second arg
	wire [7:0] constant;  // constant arg
	reg  [7:0] r[7:0];
	reg  [7:0] addrtmp;
	
	reg memio;			   // memory io operation

	assign read = write ? 0: 1;
	assign address = memio ? addrtmp : r[15];
	assign arg1 = din[7:4];
	assign arg2 = din[3:0];
	assign constant = din[7:0];

	always @(posedge clk) begin
		if (rst) begin
			r[15] <= 0;
			memio <= 0;
			write <= 0;
		end else begin
			if (memio == 0) begin
				r[15] <= r[15] + 1;   // increment PC by default
				if (r[15][0]) begin
					op <= din[7:4];
					dest <= din[3:0];
				end else begin
					// Perform the operation
					case (op)
						Inst_LOAD: begin
							memio <= 1;									// switch address to data
							addrtmp <= r[arg1] + arg2;					// set the address
							end
						Inst_STORE: begin
							memio <= 1;									// switch address to data
							write <= 1;                             	// request a write
							dout <= r[dest];                        	// output the data
							addrtmp <= r[arg1] + arg2;              	// set the address
							end
						Inst_SET: begin
							r[dest] <= constant;						// set the reg to constant
							end
					endcase
				end
			end else begin
				case (op)
					Inst_LOAD: begin
						r[dest] <= din;								// read the data
						memio <= 0;										// switch address to programm
						end
					Inst_STORE: begin
						write <= 0;										// finish a write
						memio <= 0;										// switch address to programm
						end
				endcase
			end
		end
	end
endmodule
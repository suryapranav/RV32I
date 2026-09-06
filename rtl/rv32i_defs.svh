// RV32I shared encodings.
//
// These are `include`d directly into each module that needs them rather than
// pulled in from a package. Two reasons, both about surviving Yosys:
//
//   1. Yosys's Verilog frontend rejects `import pkg::*` in the module header
//      and in the module body alike.
//   2. Scoped `pkg::NAME` references do parse, but they resolve at parse
//      time, so the package file has to be read before every module that
//      uses it. Any tool that hands Yosys the files in a different order --
//      LibreLane's GUI builds its own source list, for one -- fails to
//      elaborate. An `include` has no such ordering dependency.
//
// rv32i_pkg.sv wraps this same file, so the package still exists and there
// is still exactly one definition of every encoding.
//
// No include guard on purpose: each module wants its own copy.

/* verilator lint_off UNUSEDPARAM */
// A shared header naturally defines encodings a given module does not use.
/* verilator lint_off VARHIDDEN */
// rv32i_pkg wraps this same file, so when both are read the module-local
// copies shadow the package's. Same file, same values -- nothing to fix.

// ---- opcodes (inst[6:0]) ----
localparam logic [6:0] OP_LUI      = 7'b0110111;
localparam logic [6:0] OP_AUIPC    = 7'b0010111;
localparam logic [6:0] OP_JAL      = 7'b1101111;
localparam logic [6:0] OP_JALR     = 7'b1100111;
localparam logic [6:0] OP_BRANCH   = 7'b1100011;
localparam logic [6:0] OP_LOAD     = 7'b0000011;
localparam logic [6:0] OP_STORE    = 7'b0100011;
localparam logic [6:0] OP_OPIMM    = 7'b0010011;
localparam logic [6:0] OP_OP       = 7'b0110011;
localparam logic [6:0] OP_MISCMEM  = 7'b0001111;
localparam logic [6:0] OP_SYSTEM   = 7'b1110011;

// ---- ALU operations ----
localparam logic [3:0] ALU_ADD   = 4'd0;
localparam logic [3:0] ALU_SUB   = 4'd1;
localparam logic [3:0] ALU_SLL   = 4'd2;
localparam logic [3:0] ALU_SLT   = 4'd3;
localparam logic [3:0] ALU_SLTU  = 4'd4;
localparam logic [3:0] ALU_XOR   = 4'd5;
localparam logic [3:0] ALU_SRL   = 4'd6;
localparam logic [3:0] ALU_SRA   = 4'd7;
localparam logic [3:0] ALU_OR    = 4'd8;
localparam logic [3:0] ALU_AND   = 4'd9;
localparam logic [3:0] ALU_PASSB = 4'd10;  // for LUI

// ---- immediate formats ----
localparam logic [2:0] IMM_I = 3'd0;
localparam logic [2:0] IMM_S = 3'd1;
localparam logic [2:0] IMM_B = 3'd2;
localparam logic [2:0] IMM_U = 3'd3;
localparam logic [2:0] IMM_J = 3'd4;

// ---- forwarding select (you will use these in the pipelined version) ----
localparam logic [1:0] FWD_NONE = 2'd0;  // take the register file value
localparam logic [1:0] FWD_MEM  = 2'd1;  // forward from EX/MEM
localparam logic [1:0] FWD_WB   = 2'd2;  // forward from MEM/WB

/* verilator lint_on VARHIDDEN */
/* verilator lint_on UNUSEDPARAM */

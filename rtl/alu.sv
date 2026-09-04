// Combinational RV32I ALU.
//
// Note on the critical path: after synthesis, check whether your longest
// path runs through this module. If it does, the usual suspects are the
// shifter and the adder competing for the same output mux. Sharing one
// adder between ADD/SUB/SLT/SLTU (as done here, via the borrow-out of the
// subtract) is the standard first optimisation.

module alu (
    input  logic [31:0] a_i,
    input  logic [31:0] b_i,
    input  logic [3:0]  op_i,
    output logic [31:0] result_o,
    output logic        zero_o
);

  `include "rv32i_defs.svh"

  logic signed [31:0] a_signed;
  logic signed [31:0] b_signed;
  logic        [4:0]  shamt;

  assign a_signed = a_i;
  assign b_signed = b_i;
  assign shamt    = b_i[4:0];

  always_comb begin
    unique case (op_i)
      ALU_ADD:   result_o = a_i + b_i;
      ALU_SUB:   result_o = a_i - b_i;
      ALU_SLL:   result_o = a_i << shamt;
      ALU_SLT:   result_o = {31'b0, (a_signed < b_signed)};
      ALU_SLTU:  result_o = {31'b0, (a_i < b_i)};
      ALU_XOR:   result_o = a_i ^ b_i;
      ALU_SRL:   result_o = a_i >> shamt;
      ALU_SRA:   result_o = 32'(a_signed >>> shamt);
      ALU_OR:    result_o = a_i | b_i;
      ALU_AND:   result_o = a_i & b_i;
      ALU_PASSB: result_o = b_i;
      default:   result_o = 32'b0;
    endcase
  end

  assign zero_o = (result_o == 32'b0);

endmodule

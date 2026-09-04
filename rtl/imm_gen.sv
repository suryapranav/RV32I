// Immediate generator.
//
// The bit-scrambling in the B and J formats is not arbitrary: RISC-V places
// each immediate bit at a fixed position across all formats so the muxes
// feeding this unit stay shallow. Worth being able to explain in an
// interview -- it is a favourite question.

module imm_gen (
    input  logic [31:0] inst_i,
    input  logic [2:0]  imm_sel_i,
    output logic [31:0] imm_o
);

  `include "rv32i_defs.svh"

  always_comb begin
    unique case (imm_sel_i)
      IMM_I: imm_o = {{20{inst_i[31]}}, inst_i[31:20]};

      IMM_S: imm_o = {{20{inst_i[31]}}, inst_i[31:25], inst_i[11:7]};

      IMM_B: imm_o = {{19{inst_i[31]}}, inst_i[31], inst_i[7],
                      inst_i[30:25], inst_i[11:8], 1'b0};

      IMM_U: imm_o = {inst_i[31:12], 12'b0};

      IMM_J: imm_o = {{11{inst_i[31]}}, inst_i[31], inst_i[19:12],
                      inst_i[20], inst_i[30:21], 1'b0};

      default: imm_o = 32'b0;
    endcase
  end

endmodule

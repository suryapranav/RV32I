// RV32I core top level.
//
// Single-cycle implementation: fetch, decode, execute, memory and writeback
// all settle combinationally within one clock, so exactly one instruction
// retires per cycle. The [PIPELINED ONLY] work (stage registers, forwarding,
// hazard interlock, flush) is not here yet -- see README build order.
//
// Memory lives OUTSIDE this module, behind these ports. Do not instantiate
// memory arrays in here: sky130's open flow has no SRAM macro in the base
// LibreLane setup, so any array you declare gets built out of flip-flops
// and your area report becomes meaningless. Keeping memory external is
// also what makes this module synthesizable on its own.
//
// Both memory ports are assumed to answer combinationally (that is what
// tb/tb_top.sv provides), so instr_gnt_i / data_gnt_i are unused here. They
// become real handshakes only once the pipeline has to stall on memory.
//
// The retire interface at the bottom is what the cocotb testbench watches
// to step the golden model in lockstep. It is registered: the values held
// after a clock edge describe the instruction that committed on that edge.

module rv32i_core #(
    parameter logic [31:0] RESET_ADDR = 32'h0000_0000
) (
    input  logic        clk_i,
    input  logic        rst_ni,          // active-low synchronous reset

    // ---- instruction memory (read only, assumed 1-cycle synchronous) ----
    output logic [31:0] instr_addr_o,
    output logic        instr_req_o,
    input  logic [31:0] instr_rdata_i,
    input  logic        instr_gnt_i,     // tie high for a simple memory

    // ---- data memory ----
    output logic [31:0] data_addr_o,
    output logic        data_req_o,
    output logic        data_we_o,
    output logic [3:0]  data_be_o,       // byte enables, for SB/SH
    output logic [31:0] data_wdata_o,
    input  logic [31:0] data_rdata_i,
    input  logic        data_gnt_i,      // tie high for a simple memory

    // ---- retire interface: testbench observability, not architectural ----
    output logic        retire_valid_o,  // pulses high for one cycle per retired instruction
    output logic [31:0] retire_pc_o,     // PC of the instruction that just retired
    output logic [31:0] retire_inst_o,   // its encoding
    output logic        retire_rd_we_o,  // did it write a register?
    output logic [4:0]  retire_rd_addr_o,
    output logic [31:0] retire_rd_wdata_o
);

  `include "rv32i_defs.svh"

  // ---- writeback source select ----
  localparam logic [1:0] WB_ALU = 2'd0;  // ALU result
  localparam logic [1:0] WB_MEM = 2'd1;  // load data
  localparam logic [1:0] WB_PC4 = 2'd2;  // link address, for JAL/JALR

  // ---- ALU operand selects ----
  localparam logic A_RS1 = 1'b0;
  localparam logic A_PC  = 1'b1;  // AUIPC
  localparam logic B_RS2 = 1'b0;
  localparam logic B_IMM = 1'b1;

  // ------------------------------------------------------------------
  // Program counter
  // ------------------------------------------------------------------
  logic [31:0] pc_q, pc_d;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      pc_q <= RESET_ADDR;
    end else begin
      pc_q <= pc_d;
    end
  end

  // ------------------------------------------------------------------
  // Register file
  // ------------------------------------------------------------------
  logic [4:0]  rf_raddr_a, rf_raddr_b, rf_waddr;
  logic [31:0] rf_rdata_a, rf_rdata_b, rf_wdata;
  logic        rf_we;

  // WRITE_FIRST is off here on purpose. A single-cycle core computes the
  // writeback value from the operands it reads in the same cycle, so the
  // register file's read-during-write bypass would close a combinational
  // loop (rdata_a -> ALU -> wdata -> rdata_a) for any instruction whose rd
  // is also a source. The write lands on the clock edge instead. Turn the
  // bypass back on in the pipelined version, where ID and WB hold different
  // instructions and it saves a WB->ID forwarding path.
  regfile #(
      .WRITE_FIRST (1'b0)
  ) u_regfile (
      .clk_i     (clk_i),
      .rst_ni    (rst_ni),
      .raddr_a_i (rf_raddr_a),
      .rdata_a_o (rf_rdata_a),
      .raddr_b_i (rf_raddr_b),
      .rdata_b_o (rf_rdata_b),
      .we_i      (rf_we),
      .waddr_i   (rf_waddr),
      .wdata_i   (rf_wdata)
  );

  // ------------------------------------------------------------------
  // Immediate generation
  // ------------------------------------------------------------------
  logic [2:0]  imm_sel;
  logic [31:0] imm;

  imm_gen u_imm_gen (
      .inst_i    (instr_rdata_i),   // TODO: in the pipelined version this
      .imm_sel_i (imm_sel),         //       comes from the ID/EX register
      .imm_o     (imm)
  );

  // ------------------------------------------------------------------
  // ALU
  // ------------------------------------------------------------------
  logic [31:0] alu_a, alu_b, alu_result;
  logic [3:0]  alu_op;
  logic        alu_zero;

  alu u_alu (
      .a_i      (alu_a),
      .b_i      (alu_b),
      .op_i     (alu_op),
      .result_o (alu_result),
      .zero_o   (alu_zero)
  );

  // ------------------------------------------------------------------
  // Instruction fields
  // ------------------------------------------------------------------
  logic [6:0] opcode;
  logic [2:0] funct3;
  logic       funct7b5;   // inst[30]: ADD/SUB and SRL/SRA discriminator

  assign opcode   = instr_rdata_i[6:0];
  assign funct3   = instr_rdata_i[14:12];
  assign funct7b5 = instr_rdata_i[30];

  assign rf_raddr_a = instr_rdata_i[19:15];
  assign rf_raddr_b = instr_rdata_i[24:20];
  assign rf_waddr   = instr_rdata_i[11:7];

  // ------------------------------------------------------------------
  // Decoder
  // ------------------------------------------------------------------
  logic       alu_a_sel, alu_b_sel;
  logic       mem_req, mem_we;
  logic       is_branch, is_jal, is_jalr;
  logic [1:0] wb_sel;

  // funct3 -> ALU op, shared by OP and OP-IMM. inst[30] picks SRA over SRL
  // for both (SRAI), but only OP may turn ADD into SUB.
  logic [3:0] alu_op_arith;

  always_comb begin
    unique case (funct3)
      3'b000: alu_op_arith = ALU_ADD;
      3'b001: alu_op_arith = ALU_SLL;
      3'b010: alu_op_arith = ALU_SLT;
      3'b011: alu_op_arith = ALU_SLTU;
      3'b100: alu_op_arith = ALU_XOR;
      3'b101: alu_op_arith = funct7b5 ? ALU_SRA : ALU_SRL;
      3'b110: alu_op_arith = ALU_OR;
      3'b111: alu_op_arith = ALU_AND;
    endcase
  end

  always_comb begin
    // Defaults describe an inert instruction: no architectural effect.
    alu_op    = ALU_ADD;
    imm_sel   = IMM_I;
    rf_we     = 1'b0;
    alu_a_sel = A_RS1;
    alu_b_sel = B_IMM;
    mem_req   = 1'b0;
    mem_we    = 1'b0;
    is_branch = 1'b0;
    is_jal    = 1'b0;
    is_jalr   = 1'b0;
    wb_sel    = WB_ALU;

    unique case (opcode)
      OP_LUI: begin
        imm_sel = IMM_U;
        alu_op  = ALU_PASSB;   // rd = imm, the ALU just passes b through
        rf_we   = 1'b1;
      end

      OP_AUIPC: begin
        imm_sel   = IMM_U;
        alu_a_sel = A_PC;      // rd = pc + imm
        rf_we     = 1'b1;
      end

      OP_JAL: begin
        imm_sel = IMM_J;
        is_jal  = 1'b1;
        rf_we   = 1'b1;
        wb_sel  = WB_PC4;      // rd = link address
      end

      OP_JALR: begin
        imm_sel = IMM_I;       // the ALU computes rs1 + imm, the target
        is_jalr = 1'b1;
        rf_we   = 1'b1;
        wb_sel  = WB_PC4;
      end

      OP_BRANCH: begin
        imm_sel   = IMM_B;
        is_branch = 1'b1;      // compared in the branch unit, not the ALU
      end

      OP_LOAD: begin
        imm_sel = IMM_I;       // address = rs1 + imm
        rf_we   = 1'b1;
        mem_req = 1'b1;
        wb_sel  = WB_MEM;
      end

      OP_STORE: begin
        imm_sel = IMM_S;
        mem_req = 1'b1;
        mem_we  = 1'b1;
      end

      OP_OPIMM: begin
        imm_sel = IMM_I;
        alu_op  = alu_op_arith;
        rf_we   = 1'b1;
      end

      OP_OP: begin
        alu_b_sel = B_RS2;
        alu_op    = (funct7b5 && (funct3 == 3'b000)) ? ALU_SUB : alu_op_arith;
        rf_we     = 1'b1;
      end

      OP_MISCMEM, OP_SYSTEM: begin
        // FENCE is a no-op on a single-hart in-order core; ECALL/EBREAK are
        // treated as no-ops too -- the testbench halts on them.
      end

      default: begin
        // Illegal encoding: retire with no architectural effect.
      end
    endcase
  end

  // ------------------------------------------------------------------
  // ALU operand muxes
  // ------------------------------------------------------------------
  assign alu_a = (alu_a_sel == A_PC)  ? pc_q : rf_rdata_a;
  assign alu_b = (alu_b_sel == B_IMM) ? imm  : rf_rdata_b;

  // ------------------------------------------------------------------
  // Branch unit
  //
  // A dedicated comparator rather than alu_zero: the ALU is busy forming the
  // target/address, and BLT/BGE need a signed compare that ALU_SUB's zero
  // flag cannot give.
  // ------------------------------------------------------------------
  logic cmp_eq, cmp_lt, cmp_ltu, branch_cond, branch_taken;

  assign cmp_eq  = (rf_rdata_a == rf_rdata_b);
  assign cmp_lt  = ($signed(rf_rdata_a) < $signed(rf_rdata_b));
  assign cmp_ltu = (rf_rdata_a < rf_rdata_b);

  always_comb begin
    unique case (funct3)
      3'b000:  branch_cond =  cmp_eq;   // BEQ
      3'b001:  branch_cond = ~cmp_eq;   // BNE
      3'b100:  branch_cond =  cmp_lt;   // BLT
      3'b101:  branch_cond = ~cmp_lt;   // BGE
      3'b110:  branch_cond =  cmp_ltu;  // BLTU
      3'b111:  branch_cond = ~cmp_ltu;  // BGEU
      default: branch_cond = 1'b0;      // 010/011 are reserved
    endcase
  end

  assign branch_taken = is_branch && branch_cond;

  // ------------------------------------------------------------------
  // Next PC
  // ------------------------------------------------------------------
  logic [31:0] pc_plus4, pc_target;

  assign pc_plus4  = pc_q + 32'd4;
  assign pc_target = pc_q + imm;   // B-type and J-type are both PC-relative

  always_comb begin
    if (is_jalr) begin
      // JALR target is rs1 + imm with bit 0 cleared, per the spec.
      pc_d = {alu_result[31:1], 1'b0};
    end else if (is_jal || branch_taken) begin
      pc_d = pc_target;
    end else begin
      pc_d = pc_plus4;
    end
    // TODO: [PIPELINED ONLY] hold pc_q when the hazard unit asserts a stall.
  end

  // ------------------------------------------------------------------
  // Load / store: byte enables, write lane alignment, read extension
  // ------------------------------------------------------------------
  logic [1:0]  mem_offset;   // byte offset within the addressed word
  logic [7:0]  mem_byte;     // the addressed byte, brought to the bottom
  logic [15:0] mem_half;     // the addressed half word
  logic [31:0] load_data;

  assign mem_offset = alu_result[1:0];

  always_comb begin
    unique case (mem_offset)
      2'b00:   mem_byte = data_rdata_i[7:0];
      2'b01:   mem_byte = data_rdata_i[15:8];
      2'b10:   mem_byte = data_rdata_i[23:16];
      default: mem_byte = data_rdata_i[31:24];
    endcase
  end

  assign mem_half = mem_offset[1] ? data_rdata_i[31:16] : data_rdata_i[15:0];

  always_comb begin
    unique case (funct3[1:0])
      2'b00:   data_be_o = 4'b0001 << mem_offset;              // byte
      2'b01:   data_be_o = mem_offset[1] ? 4'b1100 : 4'b0011;  // half
      default: data_be_o = 4'b1111;                            // word
    endcase
  end

  always_comb begin
    unique case (funct3)
      3'b000:  load_data = {{24{mem_byte[7]}},  mem_byte};  // LB
      3'b001:  load_data = {{16{mem_half[15]}}, mem_half};  // LH
      3'b100:  load_data = { 24'b0,             mem_byte};  // LBU
      3'b101:  load_data = { 16'b0,             mem_half};  // LHU
      default: load_data = data_rdata_i;                    // LW
    endcase
  end

  // ------------------------------------------------------------------
  // Writeback mux
  // ------------------------------------------------------------------
  always_comb begin
    unique case (wb_sel)
      WB_MEM:  rf_wdata = load_data;
      WB_PC4:  rf_wdata = pc_plus4;
      default: rf_wdata = alu_result;
    endcase
  end

  // ------------------------------------------------------------------
  // Memory interface
  // ------------------------------------------------------------------
  assign instr_addr_o = pc_q;
  assign instr_req_o  = 1'b1;

  assign data_addr_o  = alu_result;
  assign data_req_o   = mem_req && rst_ni;  // never store while in reset
  assign data_we_o    = mem_we;

  // Stores replicate the data across the whole word and let the byte enables
  // decide which lane lands -- cheaper than shifting it into position.
  always_comb begin
    unique case (funct3[1:0])
      2'b00:   data_wdata_o = {4{rf_rdata_b[7:0]}};   // SB
      2'b01:   data_wdata_o = {2{rf_rdata_b[15:0]}};  // SH
      default: data_wdata_o = rf_rdata_b;             // SW
    endcase
  end

  // ------------------------------------------------------------------
  // Retire interface
  //
  // Registered, so after a clock edge these describe the instruction that
  // committed on that edge -- which is what the lockstep monitor samples.
  // ------------------------------------------------------------------
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      retire_valid_o    <= 1'b0;
      retire_pc_o       <= RESET_ADDR;
      retire_inst_o     <= 32'b0;
      retire_rd_we_o    <= 1'b0;
      retire_rd_addr_o  <= 5'b0;
      retire_rd_wdata_o <= 32'b0;
    end else begin
      retire_valid_o    <= 1'b1;             // single-cycle: one per cycle
      retire_pc_o       <= pc_q;
      retire_inst_o     <= instr_rdata_i;
      retire_rd_we_o    <= rf_we && (rf_waddr != 5'b0);  // x0 is never written
      retire_rd_addr_o  <= rf_waddr;
      retire_rd_wdata_o <= rf_wdata;
    end
  end

  // Unused in the single-cycle build: both memories answer combinationally,
  // and the branch unit has its own comparator.
  logic _unused;
  assign _unused = &{1'b0, instr_gnt_i, data_gnt_i, alu_zero};

endmodule

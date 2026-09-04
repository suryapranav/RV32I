// Simulation-only top level: core + behavioural unified memory.
//
// NOT SYNTHESIZED. Synthesis runs against rv32i_core alone -- see
// synth/synth.tcl. Keeping the memory here rather than inside the core is
// what lets the core synthesize to a sensible area on sky130.
//
// The memory is a simple word-addressed array with combinational reads,
// which is easier to bring up than a synchronous one. Once the core works,
// switching this to a 1-cycle synchronous read is a good way to prove your
// pipeline actually handles memory latency.

module tb_top #(
    parameter int unsigned MEM_WORDS = 4096  // 16 KB
) (
    input  logic clk_i,
    input  logic rst_ni,

    // exposed so cocotb can compare against the golden model
    output logic        retire_valid_o,
    output logic [31:0] retire_pc_o,
    output logic [31:0] retire_inst_o,
    output logic        retire_rd_we_o,
    output logic [4:0]  retire_rd_addr_o,
    output logic [31:0] retire_rd_wdata_o
);

  logic [31:0] instr_addr, instr_rdata;
  logic        instr_req;

  logic [31:0] data_addr, data_wdata, data_rdata;
  logic        data_req, data_we;
  logic [3:0]  data_be;

  // Public so cocotb can preload programs via hierarchical reference:
  //   dut.u_mem.mem.value = ...   (or the Verilator public-flat equivalent)
  /* verilator public_module */
  logic [31:0] mem [MEM_WORDS];

  // ---- instruction port: combinational read ----
  assign instr_rdata = mem[instr_addr[$clog2(MEM_WORDS)+1:2]];

  // ---- data port: combinational read, synchronous byte-enabled write ----
  assign data_rdata = mem[data_addr[$clog2(MEM_WORDS)+1:2]];

  always_ff @(posedge clk_i) begin
    if (data_req && data_we) begin
      if (data_be[0]) mem[data_addr[$clog2(MEM_WORDS)+1:2]][7:0]   <= data_wdata[7:0];
      if (data_be[1]) mem[data_addr[$clog2(MEM_WORDS)+1:2]][15:8]  <= data_wdata[15:8];
      if (data_be[2]) mem[data_addr[$clog2(MEM_WORDS)+1:2]][23:16] <= data_wdata[23:16];
      if (data_be[3]) mem[data_addr[$clog2(MEM_WORDS)+1:2]][31:24] <= data_wdata[31:24];
    end
  end

  rv32i_core u_core (
      .clk_i             (clk_i),
      .rst_ni            (rst_ni),

      .instr_addr_o      (instr_addr),
      .instr_req_o       (instr_req),
      .instr_rdata_i     (instr_rdata),
      .instr_gnt_i       (1'b1),

      .data_addr_o       (data_addr),
      .data_req_o        (data_req),
      .data_we_o         (data_we),
      .data_be_o         (data_be),
      .data_wdata_o      (data_wdata),
      .data_rdata_i      (data_rdata),
      .data_gnt_i        (1'b1),

      .retire_valid_o    (retire_valid_o),
      .retire_pc_o       (retire_pc_o),
      .retire_inst_o     (retire_inst_o),
      .retire_rd_we_o    (retire_rd_we_o),
      .retire_rd_addr_o  (retire_rd_addr_o),
      .retire_rd_wdata_o (retire_rd_wdata_o)
  );

endmodule

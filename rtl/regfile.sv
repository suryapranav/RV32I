// 32 x 32-bit register file, 2 read ports / 1 write port.
//
// x0 is hardwired to zero: writes to index 0 are discarded and reads of
// index 0 always return zero.
//
// Read behaviour is "write-first" (internal forwarding): a read in the same
// cycle as a write to the same address returns the NEW value. In a 5-stage
// pipeline this removes the need for a separate WB-to-ID forwarding path.
// If you would rather handle that in your forwarding unit, delete the
// bypass below and make the reads purely combinational on the array --
// but then remember to add the FWD_WB case for the ID stage.
//
// Synthesis note: on sky130 this infers ~1024 flip-flops plus read muxes,
// which will dominate your cell count. That is expected and fine.

module regfile #(
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned ADDR_WIDTH = 5,
    // Same-cycle read-during-write bypass, as described above. Leave it on
    // for the pipelined core; a single-cycle core must turn it off, because
    // there the write data is computed from the values read in the same
    // cycle and the bypass would close a combinational loop.
    parameter logic        WRITE_FIRST = 1'b1
) (
    input  logic                  clk_i,
    input  logic                  rst_ni,      // active-low synchronous reset

    input  logic [ADDR_WIDTH-1:0] raddr_a_i,
    output logic [DATA_WIDTH-1:0] rdata_a_o,

    input  logic [ADDR_WIDTH-1:0] raddr_b_i,
    output logic [DATA_WIDTH-1:0] rdata_b_o,

    input  logic                  we_i,
    input  logic [ADDR_WIDTH-1:0] waddr_i,
    input  logic [DATA_WIDTH-1:0] wdata_i
);

  localparam int unsigned NUM_REGS = 1 << ADDR_WIDTH;

  logic [DATA_WIDTH-1:0] mem [NUM_REGS];

  // Writes never land on x0.
  logic write_en;
  assign write_en = we_i && (waddr_i != '0);

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      for (int unsigned i = 0; i < NUM_REGS; i++) begin
        mem[i] <= '0;
      end
    end else if (write_en) begin
      mem[waddr_i] <= wdata_i;
    end
  end

  // Combinational reads with optional same-cycle write bypass; x0 reads zero.
  always_comb begin
    if (raddr_a_i == '0) begin
      rdata_a_o = '0;
    end else if (WRITE_FIRST && write_en && (waddr_i == raddr_a_i)) begin
      rdata_a_o = wdata_i;
    end else begin
      rdata_a_o = mem[raddr_a_i];
    end
  end

  always_comb begin
    if (raddr_b_i == '0) begin
      rdata_b_o = '0;
    end else if (WRITE_FIRST && write_en && (waddr_i == raddr_b_i)) begin
      rdata_b_o = wdata_i;
    end else begin
      rdata_b_o = mem[raddr_b_i];
    end
  end

endmodule

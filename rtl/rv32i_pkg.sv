// RV32I shared definitions.
//
// Kept in the synthesizable SystemVerilog subset that both Verilator and
// Yosys accept: parameters and localparams, no structs in port lists, no
// interfaces, no dynamic types.
//
// The encodings themselves live in rv32i_defs.svh, which the RTL modules
// include directly -- Yosys cannot consume this package (no `import`, and
// scoped references impose a file-ordering dependency the LibreLane GUI does
// not honour). The package is kept so the definitions are also available in
// package form, from a single source of truth.

package rv32i_pkg;

`include "rv32i_defs.svh"

endpackage

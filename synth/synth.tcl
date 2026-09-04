# Yosys synthesis: rv32i_core -> sky130 standard cells.
#
# Run via `make synth`. Synthesizes the CORE ONLY -- tb_top and its memory
# array are simulation constructs and are deliberately excluded.

set lib      $::env(LIB_TT)
set period   $::env(CLK_PERIOD_NS)
set build    $::env(BUILD)
set top      rv32i_core

# abc wants the delay target in picoseconds.
set period_ps [expr {$period * 1000.0}]

yosys read_verilog -sv rtl/rv32i_pkg.sv
yosys read_verilog -sv rtl/alu.sv
yosys read_verilog -sv rtl/regfile.sv
yosys read_verilog -sv rtl/imm_gen.sv
yosys read_verilog -sv rtl/rv32i_core.sv

yosys hierarchy -check -top $top

# Generic synthesis. -flatten helps abc optimise across module boundaries;
# drop it if you want per-module area attribution in the stat report.
yosys synth -top $top -flatten

# Map sequential elements, then combinational logic, to real cells.
yosys dfflibmap -liberty $lib
yosys abc -liberty $lib -D $period_ps
yosys setundef -zero
yosys splitnets
yosys opt_clean -purge

# Reports. `stat` gives you the cell count and area for your resume line.
yosys tee -o $build/stat.txt stat -liberty $lib
yosys tee -o $build/check.txt check

yosys write_verilog -noattr -noexpr -nohex -nodec $build/${top}_netlist.v
yosys write_json $build/${top}.json

puts "----------------------------------------------------------"
puts "netlist : $build/${top}_netlist.v"
puts "area    : see $build/stat.txt"
puts "next    : make sta CLK_PERIOD_NS=$period"
puts "----------------------------------------------------------"

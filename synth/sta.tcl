# OpenSTA: post-synthesis timing on the Yosys netlist.
#
# Run via `make sta`. This is where your resume number comes from: the
# worst-slack figure at a given clock period tells you the frequency you
# actually close at, and `report_checks` tells you which path is limiting.
#
# Method: sweep CLK_PERIOD_NS downward until slack goes negative. The
# smallest period with non-negative slack is your Fmax. Then read the
# critical path and be ready to say, in one sentence, what it runs through.

set lib    $::env(LIB_TT)
set build  $::env(BUILD)
set period $::env(CLK_PERIOD_NS)
set top    rv32i_core

read_liberty $lib
read_verilog $build/${top}_netlist.v
link_design $top

create_clock -name clk -period $period [get_ports clk_i]

# Conservative I/O timing so the report reflects the core, not the pads.
set_input_delay  -clock clk [expr {$period * 0.2}] \
    [remove_from_collection [all_inputs] [get_ports clk_i]]
set_output_delay -clock clk [expr {$period * 0.2}] [all_outputs]

# A realistic load and drive keeps the numbers honest.
set_load 0.05 [all_outputs]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 \
    [remove_from_collection [all_inputs] [get_ports clk_i]]

puts "\n=================== WORST SLACK ==================="
report_worst_slack -max

puts "\n=================== CRITICAL PATH ================="
report_checks -path_delay max -fields {slew cap input net fanout} -digits 4

puts "\n=================== HOLD ==========================="
report_checks -path_delay min -digits 4

puts "\n=================== AREA / POWER ==================="
report_design_area
report_power

puts "\nClock period: $period ns  ->  [expr {1000.0 / $period}] MHz target"

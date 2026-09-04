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

# Constraints come from the shared SDC so that `make sta` and the LibreLane
# flow report the same numbers. It reads the period from CLK_PERIOD_NS, which
# the Makefile puts in the environment.
read_sdc synth/rv32i_core.sdc

puts "\n=================== WORST SLACK ==================="
report_worst_slack -max

puts "\n=================== CRITICAL PATH ================="
report_checks -path_delay max -fields {slew cap input net fanout} -digits 4 -group_count 10

puts "\n=================== HOLD ==========================="
report_checks -path_delay min -digits 4

puts "\n=================== AREA / POWER ==================="
report_design_area
report_power

puts "\nClock period: $period ns  ->  [expr {1000.0 / $period}] MHz target"

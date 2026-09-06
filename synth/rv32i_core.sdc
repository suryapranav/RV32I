# Timing constraints for rv32i_core.
#
# Read by LibreLane (PNR_SDC_FILE / SIGNOFF_SDC_FILE / RCX_SDC_FILE) and by
# `make sta`, so the flow and the local OpenSTA run constrain the design
# identically.
#
# Setting PNR_SDC_FILE replaces LibreLane's base.sdc outright, so everything
# it provided is restated here -- clock, uncertainty, transition, drive, load,
# design rule limits, timing derate and clock propagation. The one thing that
# differs on purpose is the I/O delay budget; see below.
#
# Every command here is one base.sdc itself uses, so it stays inside the
# subset this OpenSTA build implements. In particular there is no
# remove_from_collection: that is a Synopsys command, and OpenSTA does not
# have it. The clock is excluded from the input list with lsearch/lreplace,
# exactly as base.sdc does it.
#
# ---------------------------------------------------------------------------
# Where the I/O numbers come from
#
# Memory lives outside this core (see tb/tb_top.sv), and in the testbench it
# answers combinationally, so the real fetch loop is
#
#     pc_q -> instr_addr_o -> [memory] -> instr_rdata_i -> datapath -> flop
#
# all within one clock. The I/O delays below are the budget for that external
# memory: MEM_ACCESS on the way out (address setup at the memory) and the same
# on the way back (read data valid after the memory sees the address).
#
# They are absolute nanoseconds, not a percentage of the clock, on purpose. An
# SRAM's access time does not shrink because you tightened your clock, so a
# percentage budget quietly flatters an Fmax sweep -- it relaxes exactly as
# the design gets harder. base.sdc charges IO_DELAY_CONSTRAINT = 20% per side,
# i.e. 8 ns of a 20 ns cycle, on a core where every one of the worst 1002
# setup paths starts at instr_rdata_i.
#
# MEM_ACCESS is a budget, not a measurement. Put a real memory behind these
# ports and replace it with that memory's access and setup numbers.
# ---------------------------------------------------------------------------

proc env_or {name default} {
    if { [info exists ::env($name)] && $::env($name) ne "" } {
        return $::env($name)
    }
    return $default
}

# ---- clock ----------------------------------------------------------------
# CLOCK_PERIOD is what LibreLane exports; CLK_PERIOD_NS is what `make sta`
# passes. Accept either so a period sweep works from both directions.
set clk_period [env_or CLOCK_PERIOD [env_or CLK_PERIOD_NS 20.0]]
set clk_port   [env_or CLOCK_PORT clk_i]

puts "\[INFO] rv32i_core.sdc: clock $clk_port, period $clk_period ns"

create_clock -name $clk_port -period $clk_period [get_ports $clk_port]
set clocks [get_clocks $clk_port]

set_clock_uncertainty [env_or CLOCK_UNCERTAINTY_CONSTRAINT 0.25] $clocks
set_clock_transition  [env_or CLOCK_TRANSITION_CONSTRAINT  0.15] $clocks

# ---- external interface budgets -------------------------------------------
set MEM_ACCESS 2.0   ;# external memory access / setup budget, ns
set CTRL_DELAY 1.0   ;# rst_ni, arriving from system-level logic
set DBG_DELAY  2.0   ;# retire_* -- observability, not architectural

# Exclude the clock from the input list the way base.sdc does.
set clk_input         [get_port $clk_port]
set clk_indx          [lsearch [all_inputs] $clk_input]
set all_inputs_wo_clk [lreplace [all_inputs] $clk_indx $clk_indx ""]

# Blanket the memory budget over the interface, then override the two groups
# that are not memory. A later set_input_delay/set_output_delay without
# -add_delay replaces the earlier one for that port.
set_input_delay  $MEM_ACCESS -clock $clocks $all_inputs_wo_clk
set_output_delay $MEM_ACCESS -clock $clocks [all_outputs]

set_input_delay  $CTRL_DELAY -clock $clocks [get_ports rst_ni]
set_output_delay $DBG_DELAY  -clock $clocks [get_ports retire_*]

# ---- drive and load -------------------------------------------------------
set drv     [env_or SYNTH_DRIVING_CELL     "sky130_fd_sc_hd__inv_2/Y"]
set clk_drv [env_or SYNTH_CLK_DRIVING_CELL $drv]

set_driving_cell -lib_cell [lindex [split $drv "/"] 0] \
                 -pin      [lindex [split $drv "/"] 1] $all_inputs_wo_clk
set_driving_cell -lib_cell [lindex [split $clk_drv "/"] 0] \
                 -pin      [lindex [split $clk_drv "/"] 1] $clk_input

set_load [expr {[env_or OUTPUT_CAP_LOAD 33.442] / 1000.0}] [all_outputs]

# ---- design rule limits ---------------------------------------------------
set_max_fanout      [env_or MAX_FANOUT_CONSTRAINT     10]   [current_design]
set_max_transition  [env_or MAX_TRANSITION_CONSTRAINT 0.75] [current_design]
set_max_capacitance [env_or MAX_CAPACITANCE_CONSTRAINT 0.2] [current_design]

# ---- derate and clock propagation -----------------------------------------
# base.sdc applies both. Omitting them would quietly relax signoff.
set derate [expr {[env_or TIME_DERATING_CONSTRAINT 5] / 100.0}]
set_timing_derate -early [expr {1 - $derate}]
set_timing_derate -late  [expr {1 + $derate}]

if { [env_or OPENLANE_SDC_IDEAL_CLOCKS 0] } {
    unset_propagated_clock [all_clocks]
} else {
    set_propagated_clock [all_clocks]
}

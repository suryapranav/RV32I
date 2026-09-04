# Timing constraints for rv32i_core.
#
# Read by LibreLane (PNR_SDC_FILE / SIGNOFF_SDC_FILE) and by `make sta`, so
# the flow and the local OpenSTA run constrain the design identically. Before
# this file existed the two disagreed: LibreLane fell back to its generic
# base.sdc and synth/sta.tcl carried its own inline copy.
#
# NOTE: setting PNR_SDC_FILE/SIGNOFF_SDC_FILE replaces the fallback entirely,
# so everything the fallback provided has to be restated here -- clock,
# uncertainty, I/O delays, drive/load, and the design rule limits.
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
# percentage budget quietly flatters an Fmax sweep -- the budget shrinks along
# with the period and the design looks better than it is. LibreLane's fallback
# charges IO_DELAY_CONSTRAINT = 20% per side, i.e. 8 ns of a 20 ns cycle, on a
# core where every one of the worst 1002 setup paths starts at instr_rdata_i.
#
# MEM_ACCESS is a budget, not a measurement. Put a real memory behind these
# ports and replace it with that memory's access and setup numbers.
# ---------------------------------------------------------------------------

# ---- clock ----------------------------------------------------------------
# CLOCK_PERIOD is what LibreLane exports; CLK_PERIOD_NS is what `make sta`
# passes. Accept either so a period sweep works from both directions.
if { [info exists ::env(CLOCK_PERIOD)] } {
    set clk_period $::env(CLOCK_PERIOD)
} elseif { [info exists ::env(CLK_PERIOD_NS)] } {
    set clk_period $::env(CLK_PERIOD_NS)
} else {
    set clk_period 20.0
}

if { [info exists ::env(CLOCK_PORT)] } {
    set clk_port $::env(CLOCK_PORT)
} else {
    set clk_port clk_i
}

set clk_name $clk_port

create_clock -name $clk_name -period $clk_period [get_ports $clk_port]

# Matching LibreLane's CLOCK_UNCERTAINTY_CONSTRAINT / CLOCK_TRANSITION_
# CONSTRAINT defaults, so replacing the fallback does not quietly relax
# signoff.
set_clock_uncertainty 0.25 [get_clocks $clk_name]
set_clock_transition  0.15 [get_clocks $clk_name]

# ---- external interface budgets -------------------------------------------
set MEM_ACCESS  2.0   ;# external memory access / setup budget, ns
set CTRL_DELAY  1.0   ;# rst_ni, arriving from system-level logic
set DBG_DELAY   2.0   ;# retire_* -- observability, not architectural

set inputs_no_clk [remove_from_collection [all_inputs] [get_ports $clk_port]]
set mem_inputs    [remove_from_collection $inputs_no_clk [get_ports rst_ni]]

set_input_delay -clock $clk_name $MEM_ACCESS $mem_inputs
set_input_delay -clock $clk_name $CTRL_DELAY [get_ports rst_ni]

set retire_outputs [get_ports retire_*]
set mem_outputs    [remove_from_collection [all_outputs] $retire_outputs]

set_output_delay -clock $clk_name $MEM_ACCESS $mem_outputs
set_output_delay -clock $clk_name $DBG_DELAY  $retire_outputs

# ---- drive and load -------------------------------------------------------
# Without these the inputs are driven by an ideal source and the outputs see
# no load, which makes the edges -- and the numbers -- unrealistically good.
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin Y $inputs_no_clk
set_load 0.05 [all_outputs]

# ---- design rule limits ---------------------------------------------------
# Same values as LibreLane's MAX_*_CONSTRAINT defaults.
set_max_fanout     10   [current_design]
set_max_transition 0.75 [current_design]
set_max_capacitance 0.2 [current_design]

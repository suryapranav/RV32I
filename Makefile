# RV32I core -- simulation, synthesis and implementation.
#
#   make sim         cocotb regression against the golden model
#   make wave        open the last waveform in GTKWave
#   make lint        Verilator lint only (fast, run this constantly)
#   make synth       Yosys synthesis to sky130 standard cells
#   make sta         OpenSTA timing report on the synthesized netlist
#   make flow        full LibreLane RTL-to-GDSII
#   make gui         open the LibreLane result in the OpenROAD GUI
#   make clean

# ---------------------------------------------------------------- simulation
SIM           ?= verilator
TOPLEVEL_LANG ?= verilog
TOPLEVEL      := tb_top
MODULE        := test_core

RTL_DIR := $(abspath rtl)
TB_DIR  := $(abspath tb)

# Package first -- Verilator and Yosys both need it before its users.
VERILOG_SOURCES := \
	$(RTL_DIR)/rv32i_pkg.sv \
	$(RTL_DIR)/alu.sv \
	$(RTL_DIR)/regfile.sv \
	$(RTL_DIR)/imm_gen.sv \
	$(RTL_DIR)/rv32i_core.sv \
	$(TB_DIR)/tb_top.sv

export PYTHONPATH := $(TB_DIR):$(TB_DIR)/golden:$(PYTHONPATH)

# --public-flat-rw lets cocotb poke tb_top.mem to preload programs.
EXTRA_ARGS += --trace --trace-structs --public-flat-rw -Wall -Wno-fatal -I$(RTL_DIR)

COCOTB_MAKEFILES := $(shell cocotb-config --makefiles 2>/dev/null)
ifneq ($(COCOTB_MAKEFILES),)
include $(COCOTB_MAKEFILES)/Makefile.sim
endif

# ---------------------------------------------------------------- lint
.PHONY: lint
lint:
	verilator --lint-only -Wall --top-module rv32i_core -I$(RTL_DIR) \
		$(RTL_DIR)/rv32i_pkg.sv $(RTL_DIR)/alu.sv $(RTL_DIR)/regfile.sv \
		$(RTL_DIR)/imm_gen.sv $(RTL_DIR)/rv32i_core.sv

.PHONY: wave
wave:
	gtkwave dump.vcd &

# ---------------------------------------------------------------- synthesis
# PDK_ROOT is set for you inside the LibreLane nix-shell. Outside it, point
# it at your volare-installed PDK, e.g.
#   export PDK_ROOT=$HOME/.volare
PDK_ROOT ?= $(HOME)/.volare
PDK      ?= sky130A
SCL      ?= sky130_fd_sc_hd
LIB_TT   := $(PDK_ROOT)/$(PDK)/libs.ref/$(SCL)/lib/$(SCL)__tt_025C_1v80.lib

# Target clock period in nanoseconds. Start loose (20ns = 50 MHz), then
# tighten until timing fails -- that number is your result.
CLK_PERIOD_NS ?= 20.0

BUILD := build

.PHONY: synth
synth: | $(BUILD)
	LIB_TT=$(LIB_TT) CLK_PERIOD_NS=$(CLK_PERIOD_NS) BUILD=$(BUILD) \
		yosys -c synth/synth.tcl | tee $(BUILD)/synth.log

.PHONY: sta
sta: | $(BUILD)
	LIB_TT=$(LIB_TT) CLK_PERIOD_NS=$(CLK_PERIOD_NS) BUILD=$(BUILD) \
		sta -exit synth/sta.tcl | tee $(BUILD)/sta.log

$(BUILD):
	mkdir -p $(BUILD)

# ---------------------------------------------------------------- librelane
.PHONY: flow
flow:
	librelane --design-dir flow flow/config.json

.PHONY: gui
gui:
	librelane --last-run --flow openinopenroad --design-dir flow flow/config.json

.PHONY: klayout
klayout:
	librelane --last-run --flow openinklayout --design-dir flow flow/config.json

# ---------------------------------------------------------------- clean
.PHONY: clean
clean::
	rm -rf $(BUILD) sim_build dump.vcd results.xml __pycache__ \
		tb/__pycache__ tb/golden/__pycache__ obj_dir

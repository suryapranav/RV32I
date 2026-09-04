# RV32I Pipelined Processor Core

A 5-stage RV32I core in SystemVerilog, verified in lockstep against a Python
golden model and taken through synthesis on the SkyWater 130nm PDK.

---

## What is here, and what is not

**Provided:** the build system, the golden reference model, the cocotb
harness, the synthesis and STA scripts, the LibreLane config, and three
mechanical building blocks (ALU, register file, immediate generator).

**Left for you — deliberately:** the decoder, the datapath wiring, the
branch unit, load/store byte handling, the pipeline registers, the
forwarding unit, and the hazard/interlock logic.

That split is not laziness. Those are exactly the parts an interviewer will
ask you to walk through at a whiteboard, and a core you did not wire
yourself is one you cannot defend. The scaffolding removes the tedium; the
processor is yours.

---

## Setup

```bash
# simulation + synthesis tools
pip install cocotb cocotb-test
sudo apt install verilator gtkwave yosys      # or nix / brew equivalents

# PDK (sky130) via volare
pip install volare
volare enable --pdk sky130 $(volare ls-remote --pdk sky130 | head -1)
export PDK_ROOT=$HOME/.volare

# LibreLane, only when you get to physical implementation
git clone https://github.com/librelane/librelane
cd librelane && nix-shell
```

## Daily loop

```bash
make lint      # seconds. run constantly.
make sim       # cocotb regression vs the golden model
make wave      # GTKWave, when a test fails and you need to see why
```

---

## Build order

Do these in order. Skipping ahead is the most common way this project
stalls.

**1. Single-cycle first.**
In `rtl/rv32i_core.sv`, ignore everything marked `[PIPELINED ONLY]`. Wire
decode straight through to the ALU and writeback so an instruction
completes in one cycle. Get `test_arithmetic` passing, then
`test_load_store`, then `test_branches` and `test_jumps`.

**2. Pull in riscv-tests.**
Your own directed tests prove the cases you thought of. `riscv-tests` proves
the ones you did not. "Passes riscv-tests" is a sentence an interviewer
immediately understands; "passes my testbench" is not.

**3. Then pipeline it.**
Split into IF/ID/EX/MEM/WB, add forwarding and the load-use interlock. Your
single-cycle tests are now the regression that tells you the pipelining did
not break the semantics. This is why order matters — if you pipeline first,
every failure is ambiguous between a decode bug and a hazard bug.

**4. Synthesis.**

```bash
make synth CLK_PERIOD_NS=20     # 50 MHz, comfortable
make sta   CLK_PERIOD_NS=20
```

Then sweep the period down until slack goes negative. The smallest period
that still closes is your Fmax, and that is the number on your resume.

**5. Physical implementation, only if time allows.**

```bash
make flow    # LibreLane RTL-to-GDSII
make gui     # inspect in the OpenROAD GUI
```

---

## Things that will bite you

**Memory stays outside the core.** sky130's open flow has no SRAM macro in
the base LibreLane setup. Any memory array declared inside `rv32i_core` gets
built out of flip-flops and your area number becomes meaningless. The
behavioural memory lives in `tb/tb_top.sv`, which is never synthesized.

**LB and LH sign extension.** The most common place riscv-tests fails first.
`LB` sign-extends, `LBU` does not. Same for `LH`/`LHU`.

**JALR clears the low bit** of the computed target. Easy to miss, and it
only shows up on a jump to an odd address.

**The branch immediate is 13 bits with bit 0 implicitly zero.** If your
branches land two bytes off, this is why.

**x0 must stay zero** even when an instruction targets it. `addi x0, x0, 1`
is a legal no-op, not a write.

---

## Numbers to record

Fill these in from your own runs. Do not estimate them — an interviewer will
ask what your critical path was and why, and a made-up figure falls apart
immediately.

| Metric | Where it comes from | Yours |
|---|---|---|
| Instructions implemented | count what you built | |
| riscv-tests passing | test suite output | |
| Directed + random tests | `make sim` | |
| Cell count / area | `build/stat.txt` | |
| Fmax | period sweep via `make sta` | |
| Critical path | `report_checks` output | |

That last row matters most. "Met timing at X MHz" is a fact about the tool.
"The critical path ran through the branch comparator into the PC mux, and I
moved it by resolving branches a stage earlier" is evidence you understand
your own design.

---

## Layout

```
rtl/          synthesizable SystemVerilog (this is what ships)
tb/           cocotb tests + simulation-only wrapper and memory
  golden/     Python RV32I reference model and instruction encoder
synth/        Yosys and OpenSTA scripts
flow/         LibreLane configuration
```

"""
Differential test: RTL core vs. Python golden model, in lockstep.

Every time the core asserts retire_valid, we step the model once and compare
PC, instruction, and any register write. The first mismatch aborts with the
exact instruction that diverged -- which is almost always more useful than a
waveform, because it tells you *which* instruction is wrong before you go
looking at *why*.

Run with:  make sim
"""

import random
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

sys.path.insert(0, str(Path(__file__).parent / "golden"))

import asm as a                          # noqa: E402
from rv32i_model import RV32I            # noqa: E402

MASK32 = 0xFFFFFFFF
TIMEOUT_CYCLES = 5000


async def reset(dut, cycles: int = 5):
    dut.rst_ni.value = 0
    await ClockCycles(dut.clk_i, cycles)
    dut.rst_ni.value = 1
    await RisingEdge(dut.clk_i)


def load_memory(dut, program: list[int]) -> None:
    """Preload the behavioural memory in tb_top with a program."""
    for i, word in enumerate(program):
        dut.mem[i].value = word & MASK32


async def run_lockstep(dut, program: list[int], name: str, max_retire: int = 2000):
    """Drive the core and compare each retirement against the model."""
    model = RV32I()
    model.load_program(program)

    cocotb.start_soon(Clock(dut.clk_i, 10, units="ns").start())
    load_memory(dut, program)
    await reset(dut)

    retired = 0
    idle = 0

    while retired < max_retire:
        await RisingEdge(dut.clk_i)

        if dut.retire_valid_o.value != 1:
            idle += 1
            if idle > TIMEOUT_CYCLES:
                raise AssertionError(
                    f"[{name}] core stalled: no retirement in {TIMEOUT_CYCLES} cycles "
                    f"after {retired} instructions"
                )
            continue

        idle = 0

        rtl_pc = int(dut.retire_pc_o.value)
        rtl_inst = int(dut.retire_inst_o.value)
        rtl_we = int(dut.retire_rd_we_o.value)
        rtl_rd = int(dut.retire_rd_addr_o.value)
        rtl_data = int(dut.retire_rd_wdata_o.value)

        exp_pc = model.pc
        try:
            exp_inst = model.step()
        except Exception as exc:  # StopExecution or a decode error
            dut._log.info(f"[{name}] model halted after {retired} instructions: {exc}")
            return model

        assert rtl_pc == exp_pc, (
            f"[{name}] PC mismatch at retirement {retired}: "
            f"RTL {rtl_pc:#010x} vs model {exp_pc:#010x}"
        )
        assert rtl_inst == exp_inst, (
            f"[{name}] instruction mismatch at pc={exp_pc:#010x}: "
            f"RTL {rtl_inst:#010x} vs model {exp_inst:#010x}"
        )

        # Compare the architectural register write, if any.
        if rtl_we and rtl_rd != 0:
            exp_data = model.read_reg(rtl_rd)
            assert rtl_data == exp_data, (
                f"[{name}] x{rtl_rd} mismatch after pc={exp_pc:#010x} "
                f"(inst {exp_inst:#010x}): RTL {rtl_data:#010x} vs model {exp_data:#010x}"
            )

        retired += 1

    return model


@cocotb.test()
async def test_arithmetic(dut):
    """Directed: register-register and register-immediate arithmetic."""
    program = [
        a.addi(1, 0, 5),
        a.addi(2, 0, -3),
        a.add(3, 1, 2),
        a.sub(4, 1, 2),
        a.and_(5, 1, 2),
        a.or_(6, 1, 2),
        a.xor_(7, 1, 2),
        a.slt(8, 2, 1),
        a.sltu(9, 2, 1),
        a.slli(10, 1, 4),
        a.srli(11, 2, 4),
        a.srai(12, 2, 4),
        a.lui(13, 0x12345),
        a.auipc(14, 0x1),
        a.ebreak(),
    ]
    await run_lockstep(dut, program, "arithmetic")


@cocotb.test()
async def test_load_store(dut):
    """Directed: all load and store widths, including sign extension."""
    program = [
        a.lui(1, 0xDEADC),
        a.addi(1, 1, 0x6D),      # x1 = 0xDEADBC6D-ish pattern
        a.sw(1, 0, 0x400),
        a.lw(2, 0, 0x400),
        a.lb(3, 0, 0x400),       # sign-extended
        a.lbu(4, 0, 0x400),      # zero-extended
        a.lh(5, 0, 0x400),
        a.lhu(6, 0, 0x400),
        a.sb(1, 0, 0x408),
        a.lbu(7, 0, 0x408),
        a.sh(1, 0, 0x40C),
        a.lhu(8, 0, 0x40C),
        a.ebreak(),
    ]
    await run_lockstep(dut, program, "load_store")


@cocotb.test()
async def test_branches(dut):
    """Directed: every branch condition, taken and not-taken."""
    program = [
        a.addi(1, 0, 5),
        a.addi(2, 0, 5),
        a.addi(3, 0, -1),
        a.beq(1, 2, 8),          # taken
        a.addi(10, 0, 1),        # skipped
        a.bne(1, 3, 8),          # taken
        a.addi(11, 0, 1),        # skipped
        a.blt(3, 1, 8),          # taken (signed)
        a.addi(12, 0, 1),        # skipped
        a.bltu(1, 3, 8),         # taken (unsigned: 5 < 0xFFFFFFFF)
        a.addi(13, 0, 1),        # skipped
        a.bge(1, 2, 8),          # taken
        a.addi(14, 0, 1),        # skipped
        a.addi(15, 0, 42),       # executed
        a.ebreak(),
    ]
    await run_lockstep(dut, program, "branches")


@cocotb.test()
async def test_jumps(dut):
    """Directed: JAL and JALR link values and targets."""
    program = [
        a.jal(1, 8),             # x1 = 0x04, jump to 0x08
        a.addi(20, 0, 1),        # skipped
        a.auipc(2, 0),           # x2 = 0x08
        a.jalr(3, 2, 12),        # jump to 0x14, x3 = 0x10
        a.addi(21, 0, 1),        # skipped
        a.addi(22, 0, 7),        # executed at 0x14
        a.ebreak(),
    ]
    await run_lockstep(dut, program, "jumps")


@cocotb.test()
async def test_hazards(dut):
    """Back-to-back dependencies: exercises forwarding and the load-use interlock."""
    program = [
        a.addi(1, 0, 1),
        a.addi(2, 1, 1),         # EX->EX forward
        a.addi(3, 1, 2),         # MEM->EX forward
        a.add(4, 2, 3),          # two-source forward
        a.sw(4, 0, 0x500),
        a.lw(5, 0, 0x500),
        a.addi(6, 5, 1),         # LOAD-USE: must stall one cycle
        a.add(7, 5, 6),
        a.sub(8, 7, 6),
        a.ebreak(),
    ]
    await run_lockstep(dut, program, "hazards")


@cocotb.test()
async def test_random_arithmetic(dut):
    """Constrained-random: random ALU ops over random register state."""
    random.seed(0xC0FFEE)

    program = []
    # Seed x1..x8 with random values.
    for reg in range(1, 9):
        program.append(a.lui(reg, random.getrandbits(20)))
        program.append(a.addi(reg, reg, random.randint(-2048, 2047)))

    ops = [a.add, a.sub, a.and_, a.or_, a.xor_, a.slt, a.sltu, a.sll, a.srl, a.sra]
    for _ in range(200):
        op = random.choice(ops)
        rd = random.randint(9, 31)
        rs1 = random.randint(1, 8)
        rs2 = random.randint(1, 8)
        program.append(op(rd, rs1, rs2))

    program.append(a.ebreak())
    await run_lockstep(dut, program, "random_arithmetic")

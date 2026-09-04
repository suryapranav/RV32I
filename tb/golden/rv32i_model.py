"""
RV32I golden reference model.

A plain-Python instruction-set simulator for the RV32I base integer ISA.
The cocotb testbench steps this model in lockstep with the RTL and compares
architectural state (x1-x31 and PC) after every retired instruction.

This is deliberately written for clarity over speed: it is a specification
you can read, not a fast simulator.

Not implemented: FENCE/ECALL/EBREAK are decoded and treated as no-ops
(FENCE is architecturally a no-op for a single-hart in-order core; the
SYSTEM instructions raise StopExecution so a test program can halt).
"""

MASK32 = 0xFFFFFFFF


class StopExecution(Exception):
    """Raised on ECALL/EBREAK so a test program can signal completion."""

    def __init__(self, cause: str):
        super().__init__(cause)
        self.cause = cause


def sext(value: int, bits: int) -> int:
    """Sign-extend `value` from `bits` wide to a Python int."""
    sign = 1 << (bits - 1)
    return (value & (sign - 1)) - (value & sign)


def to_signed(value: int) -> int:
    return sext(value & MASK32, 32)


class RV32I:
    def __init__(self, memory: dict | None = None, pc: int = 0, mem_size: int = 1 << 16):
        # x0 is architecturally hardwired to zero; index 0 is never written.
        self.regs = [0] * 32
        self.pc = pc & MASK32
        self.mem_size = mem_size
        # Byte-addressed sparse memory. Missing bytes read as zero.
        self.mem: dict[int, int] = dict(memory) if memory else {}
        self.retired = 0

    # ---------- register file ----------

    def read_reg(self, index: int) -> int:
        return 0 if index == 0 else self.regs[index] & MASK32

    def write_reg(self, index: int, value: int) -> None:
        if index != 0:
            self.regs[index] = value & MASK32

    # ---------- memory ----------

    def load(self, addr: int, nbytes: int) -> int:
        addr &= MASK32
        value = 0
        for i in range(nbytes):
            value |= self.mem.get(addr + i, 0) << (8 * i)
        return value

    def store(self, addr: int, value: int, nbytes: int) -> None:
        addr &= MASK32
        for i in range(nbytes):
            self.mem[addr + i] = (value >> (8 * i)) & 0xFF

    def load_program(self, words: list[int], base: int = 0) -> None:
        for i, word in enumerate(words):
            self.store(base + 4 * i, word & MASK32, 4)

    # ---------- execution ----------

    def step(self) -> int:
        """Execute one instruction. Returns the instruction word executed."""
        inst = self.load(self.pc, 4)
        next_pc = (self.pc + 4) & MASK32

        opcode = inst & 0x7F
        rd = (inst >> 7) & 0x1F
        funct3 = (inst >> 12) & 0x07
        rs1 = (inst >> 15) & 0x1F
        rs2 = (inst >> 20) & 0x1F
        funct7 = (inst >> 25) & 0x7F

        a = self.read_reg(rs1)
        b = self.read_reg(rs2)

        imm_i = sext((inst >> 20) & 0xFFF, 12)
        imm_s = sext((((inst >> 25) & 0x7F) << 5) | ((inst >> 7) & 0x1F), 12)
        imm_b = sext(
            (((inst >> 31) & 0x1) << 12)
            | (((inst >> 7) & 0x1) << 11)
            | (((inst >> 25) & 0x3F) << 5)
            | (((inst >> 8) & 0xF) << 1),
            13,
        )
        imm_u = inst & 0xFFFFF000
        imm_j = sext(
            (((inst >> 31) & 0x1) << 20)
            | (((inst >> 12) & 0xFF) << 12)
            | (((inst >> 20) & 0x1) << 11)
            | (((inst >> 21) & 0x3FF) << 1),
            21,
        )

        if opcode == 0x37:  # LUI
            self.write_reg(rd, imm_u)

        elif opcode == 0x17:  # AUIPC
            self.write_reg(rd, self.pc + imm_u)

        elif opcode == 0x6F:  # JAL
            self.write_reg(rd, next_pc)
            next_pc = (self.pc + imm_j) & MASK32

        elif opcode == 0x67:  # JALR
            self.write_reg(rd, next_pc)
            # The LSB of the computed target is cleared, per the spec.
            next_pc = (a + imm_i) & MASK32 & ~1

        elif opcode == 0x63:  # BRANCH
            sa, sb = to_signed(a), to_signed(b)
            taken = {
                0x0: sa == sb,                  # BEQ
                0x1: sa != sb,                  # BNE
                0x4: sa < sb,                   # BLT
                0x5: sa >= sb,                  # BGE
                0x6: a < b,                     # BLTU
                0x7: a >= b,                    # BGEU
            }.get(funct3)
            if taken is None:
                raise ValueError(f"bad BRANCH funct3={funct3:#x} at pc={self.pc:#010x}")
            if taken:
                next_pc = (self.pc + imm_b) & MASK32

        elif opcode == 0x03:  # LOAD
            addr = (a + imm_i) & MASK32
            if funct3 == 0x0:      # LB
                self.write_reg(rd, sext(self.load(addr, 1), 8) & MASK32)
            elif funct3 == 0x1:    # LH
                self.write_reg(rd, sext(self.load(addr, 2), 16) & MASK32)
            elif funct3 == 0x2:    # LW
                self.write_reg(rd, self.load(addr, 4))
            elif funct3 == 0x4:    # LBU
                self.write_reg(rd, self.load(addr, 1))
            elif funct3 == 0x5:    # LHU
                self.write_reg(rd, self.load(addr, 2))
            else:
                raise ValueError(f"bad LOAD funct3={funct3:#x} at pc={self.pc:#010x}")

        elif opcode == 0x23:  # STORE
            addr = (a + imm_s) & MASK32
            nbytes = {0x0: 1, 0x1: 2, 0x2: 4}.get(funct3)
            if nbytes is None:
                raise ValueError(f"bad STORE funct3={funct3:#x} at pc={self.pc:#010x}")
            self.store(addr, b, nbytes)

        elif opcode == 0x13:  # OP-IMM
            shamt = (inst >> 20) & 0x1F
            if funct3 == 0x0:      # ADDI
                self.write_reg(rd, a + imm_i)
            elif funct3 == 0x2:    # SLTI
                self.write_reg(rd, int(to_signed(a) < imm_i))
            elif funct3 == 0x3:    # SLTIU
                self.write_reg(rd, int(a < (imm_i & MASK32)))
            elif funct3 == 0x4:    # XORI
                self.write_reg(rd, a ^ (imm_i & MASK32))
            elif funct3 == 0x6:    # ORI
                self.write_reg(rd, a | (imm_i & MASK32))
            elif funct3 == 0x7:    # ANDI
                self.write_reg(rd, a & (imm_i & MASK32))
            elif funct3 == 0x1:    # SLLI
                self.write_reg(rd, a << shamt)
            elif funct3 == 0x5:
                if funct7 == 0x00:  # SRLI
                    self.write_reg(rd, a >> shamt)
                elif funct7 == 0x20:  # SRAI
                    self.write_reg(rd, to_signed(a) >> shamt)
                else:
                    raise ValueError(f"bad SRLI/SRAI funct7={funct7:#x}")
            else:
                raise ValueError(f"bad OP-IMM funct3={funct3:#x} at pc={self.pc:#010x}")

        elif opcode == 0x33:  # OP
            shamt = b & 0x1F
            if funct7 == 0x00:
                if funct3 == 0x0:      # ADD
                    self.write_reg(rd, a + b)
                elif funct3 == 0x1:    # SLL
                    self.write_reg(rd, a << shamt)
                elif funct3 == 0x2:    # SLT
                    self.write_reg(rd, int(to_signed(a) < to_signed(b)))
                elif funct3 == 0x3:    # SLTU
                    self.write_reg(rd, int(a < b))
                elif funct3 == 0x4:    # XOR
                    self.write_reg(rd, a ^ b)
                elif funct3 == 0x5:    # SRL
                    self.write_reg(rd, a >> shamt)
                elif funct3 == 0x6:    # OR
                    self.write_reg(rd, a | b)
                elif funct3 == 0x7:    # AND
                    self.write_reg(rd, a & b)
            elif funct7 == 0x20:
                if funct3 == 0x0:      # SUB
                    self.write_reg(rd, a - b)
                elif funct3 == 0x5:    # SRA
                    self.write_reg(rd, to_signed(a) >> shamt)
                else:
                    raise ValueError(f"bad OP funct3={funct3:#x} with funct7=0x20")
            else:
                raise ValueError(f"bad OP funct7={funct7:#x} at pc={self.pc:#010x}")

        elif opcode == 0x0F:  # MISC-MEM (FENCE) - no-op for this core
            pass

        elif opcode == 0x73:  # SYSTEM (ECALL / EBREAK)
            raise StopExecution("ebreak" if (inst >> 20) & 0x1 else "ecall")

        else:
            raise ValueError(f"unknown opcode {opcode:#04x} at pc={self.pc:#010x}")

        self.pc = next_pc
        self.retired += 1
        return inst

    def run(self, max_steps: int = 10000) -> str:
        """Run until ECALL/EBREAK or the step budget is exhausted."""
        for _ in range(max_steps):
            try:
                self.step()
            except StopExecution as stop:
                return stop.cause
        return "timeout"

    def state(self) -> dict:
        """Architectural state snapshot, for comparison against the RTL."""
        return {
            "pc": self.pc,
            "regs": [self.read_reg(i) for i in range(32)],
        }

    def __repr__(self) -> str:
        return f"<RV32I pc={self.pc:#010x} retired={self.retired}>"

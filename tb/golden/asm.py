"""
Minimal RV32I encoder.

Enough to hand-build directed test programs without a toolchain. Once you
have riscv64-unknown-elf-gcc set up, prefer real assembly and objcopy; this
exists so you are not blocked on toolchain install.

    from asm import addi, add, lw, sw, beq, jal
    prog = [addi(1, 0, 5), addi(2, 0, 7), add(3, 1, 2)]
"""

MASK32 = 0xFFFFFFFF


def _u(value: int, bits: int) -> int:
    return value & ((1 << bits) - 1)


def r_type(opcode, rd, funct3, rs1, rs2, funct7) -> int:
    return (
        _u(funct7, 7) << 25 | _u(rs2, 5) << 20 | _u(rs1, 5) << 15
        | _u(funct3, 3) << 12 | _u(rd, 5) << 7 | _u(opcode, 7)
    ) & MASK32


def i_type(opcode, rd, funct3, rs1, imm) -> int:
    return (
        _u(imm, 12) << 20 | _u(rs1, 5) << 15 | _u(funct3, 3) << 12
        | _u(rd, 5) << 7 | _u(opcode, 7)
    ) & MASK32


def s_type(opcode, funct3, rs1, rs2, imm) -> int:
    imm = _u(imm, 12)
    return (
        (imm >> 5) << 25 | _u(rs2, 5) << 20 | _u(rs1, 5) << 15
        | _u(funct3, 3) << 12 | (imm & 0x1F) << 7 | _u(opcode, 7)
    ) & MASK32


def b_type(opcode, funct3, rs1, rs2, imm) -> int:
    imm = _u(imm, 13)
    return (
        ((imm >> 12) & 1) << 31 | ((imm >> 5) & 0x3F) << 25 | _u(rs2, 5) << 20
        | _u(rs1, 5) << 15 | _u(funct3, 3) << 12 | ((imm >> 1) & 0xF) << 8
        | ((imm >> 11) & 1) << 7 | _u(opcode, 7)
    ) & MASK32


def u_type(opcode, rd, imm) -> int:
    return ((imm & 0xFFFFF) << 12 | _u(rd, 5) << 7 | _u(opcode, 7)) & MASK32


def j_type(opcode, rd, imm) -> int:
    imm = _u(imm, 21)
    return (
        ((imm >> 20) & 1) << 31 | ((imm >> 1) & 0x3FF) << 21
        | ((imm >> 11) & 1) << 20 | ((imm >> 12) & 0xFF) << 12
        | _u(rd, 5) << 7 | _u(opcode, 7)
    ) & MASK32


# --- OP-IMM ---
def addi(rd, rs1, imm):  return i_type(0x13, rd, 0x0, rs1, imm)
def slti(rd, rs1, imm):  return i_type(0x13, rd, 0x2, rs1, imm)
def sltiu(rd, rs1, imm): return i_type(0x13, rd, 0x3, rs1, imm)
def xori(rd, rs1, imm):  return i_type(0x13, rd, 0x4, rs1, imm)
def ori(rd, rs1, imm):   return i_type(0x13, rd, 0x6, rs1, imm)
def andi(rd, rs1, imm):  return i_type(0x13, rd, 0x7, rs1, imm)
def slli(rd, rs1, sh):   return i_type(0x13, rd, 0x1, rs1, sh & 0x1F)
def srli(rd, rs1, sh):   return i_type(0x13, rd, 0x5, rs1, sh & 0x1F)
def srai(rd, rs1, sh):   return i_type(0x13, rd, 0x5, rs1, (0x20 << 5) | (sh & 0x1F))

# --- OP ---
def add(rd, rs1, rs2):  return r_type(0x33, rd, 0x0, rs1, rs2, 0x00)
def sub(rd, rs1, rs2):  return r_type(0x33, rd, 0x0, rs1, rs2, 0x20)
def sll(rd, rs1, rs2):  return r_type(0x33, rd, 0x1, rs1, rs2, 0x00)
def slt(rd, rs1, rs2):  return r_type(0x33, rd, 0x2, rs1, rs2, 0x00)
def sltu(rd, rs1, rs2): return r_type(0x33, rd, 0x3, rs1, rs2, 0x00)
def xor_(rd, rs1, rs2): return r_type(0x33, rd, 0x4, rs1, rs2, 0x00)
def srl(rd, rs1, rs2):  return r_type(0x33, rd, 0x5, rs1, rs2, 0x00)
def sra(rd, rs1, rs2):  return r_type(0x33, rd, 0x5, rs1, rs2, 0x20)
def or_(rd, rs1, rs2):  return r_type(0x33, rd, 0x6, rs1, rs2, 0x00)
def and_(rd, rs1, rs2): return r_type(0x33, rd, 0x7, rs1, rs2, 0x00)

# --- LOAD / STORE ---
def lb(rd, rs1, imm):  return i_type(0x03, rd, 0x0, rs1, imm)
def lh(rd, rs1, imm):  return i_type(0x03, rd, 0x1, rs1, imm)
def lw(rd, rs1, imm):  return i_type(0x03, rd, 0x2, rs1, imm)
def lbu(rd, rs1, imm): return i_type(0x03, rd, 0x4, rs1, imm)
def lhu(rd, rs1, imm): return i_type(0x03, rd, 0x5, rs1, imm)
def sb(rs2, rs1, imm): return s_type(0x23, 0x0, rs1, rs2, imm)
def sh(rs2, rs1, imm): return s_type(0x23, 0x1, rs1, rs2, imm)
def sw(rs2, rs1, imm): return s_type(0x23, 0x2, rs1, rs2, imm)

# --- BRANCH ---
def beq(rs1, rs2, imm):  return b_type(0x63, 0x0, rs1, rs2, imm)
def bne(rs1, rs2, imm):  return b_type(0x63, 0x1, rs1, rs2, imm)
def blt(rs1, rs2, imm):  return b_type(0x63, 0x4, rs1, rs2, imm)
def bge(rs1, rs2, imm):  return b_type(0x63, 0x5, rs1, rs2, imm)
def bltu(rs1, rs2, imm): return b_type(0x63, 0x6, rs1, rs2, imm)
def bgeu(rs1, rs2, imm): return b_type(0x63, 0x7, rs1, rs2, imm)

# --- JUMP / UPPER IMM / SYSTEM ---
def jal(rd, imm):        return j_type(0x6F, rd, imm)
def jalr(rd, rs1, imm):  return i_type(0x67, rd, 0x0, rs1, imm)
def lui(rd, imm):        return u_type(0x37, rd, imm)
def auipc(rd, imm):      return u_type(0x17, rd, imm)
def ecall():             return 0x00000073
def ebreak():            return 0x00100073
def nop():               return addi(0, 0, 0)

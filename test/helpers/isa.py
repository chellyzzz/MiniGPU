"""
Tiny-GPU ISA 编码辅助模块
根据 docs/isa.md 中的指令格式定义
"""

# 寄存器别名
R0, R1, R2, R3, R4, R5, R6, R7 = 0, 1, 2, 3, 4, 5, 6, 7
R8, R9, R10, R11, R12 = 8, 9, 10, 11, 12
BLOCK_IDX = 13   # %blockIdx (只读)
BLOCK_DIM = 14   # %blockDim (只读)
THREAD_IDX = 15  # %threadIdx (只读)


def NOP():
    """空操作"""
    return 0b0000_0000_0000_0000


def BRnzp(nzp, imm8):
    """条件分支: nzp=3位条件, imm8=目标PC"""
    return (0b0001 << 12) | ((nzp & 0b111) << 9) | (imm8 & 0xFF)


def BRn(imm8):
    """负数时跳转"""
    return BRnzp(0b100, imm8)


def BRz(imm8):
    """零时跳转"""
    return BRnzp(0b010, imm8)


def BRp(imm8):
    """正数时跳转"""
    return BRnzp(0b001, imm8)


def BR(imm8):
    """无条件跳转"""
    return BRnzp(0b111, imm8)


def CMP(rs, rt):
    """比较 Rs 和 Rt，设置 NZP 标志"""
    return (0b0010 << 12) | ((rs & 0xF) << 4) | (rt & 0xF)


def ADD(rd, rs, rt):
    """Rd = Rs + Rt"""
    return (0b0011 << 12) | ((rd & 0xF) << 8) | ((rs & 0xF) << 4) | (rt & 0xF)


def SUB(rd, rs, rt):
    """Rd = Rs - Rt"""
    return (0b0100 << 12) | ((rd & 0xF) << 8) | ((rs & 0xF) << 4) | (rt & 0xF)


def MUL(rd, rs, rt):
    """Rd = Rs * Rt"""
    return (0b0101 << 12) | ((rd & 0xF) << 8) | ((rs & 0xF) << 4) | (rt & 0xF)


def DIV(rd, rs, rt):
    """Rd = Rs / Rt"""
    return (0b0110 << 12) | ((rd & 0xF) << 8) | ((rs & 0xF) << 4) | (rt & 0xF)


def LDR(rd, rs):
    """Rd = global_data_mem[Rs]"""
    return (0b0111 << 12) | ((rd & 0xF) << 8) | ((rs & 0xF) << 4)


def STR(rs, rt):
    """global_data_mem[Rs] = Rt"""
    return (0b1000 << 12) | ((rs & 0xF) << 4) | (rt & 0xF)


def CONST(rd, imm8):
    """Rd = IMM8"""
    return (0b1001 << 12) | ((rd & 0xF) << 8) | (imm8 & 0xFF)


def RET():
    """线程结束"""
    return 0b1111_0000_0000_0000


def disassemble(instruction):
    """反汇编单条指令"""
    opcode = (instruction >> 12) & 0xF
    rd = (instruction >> 8) & 0xF
    rs = (instruction >> 4) & 0xF
    rt = instruction & 0xF
    imm8 = instruction & 0xFF
    nzp = (instruction >> 9) & 0x7
    
    opcodes = {
        0b0000: "NOP",
        0b0001: f"BR{'n' if nzp&4 else ''}{'z' if nzp&2 else ''}{'p' if nzp&1 else ''} #{imm8}",
        0b0010: f"CMP R{rs}, R{rt}",
        0b0011: f"ADD R{rd}, R{rs}, R{rt}",
        0b0100: f"SUB R{rd}, R{rs}, R{rt}",
        0b0101: f"MUL R{rd}, R{rs}, R{rt}",
        0b0110: f"DIV R{rd}, R{rs}, R{rt}",
        0b0111: f"LDR R{rd}, R{rs}",
        0b1000: f"STR R{rs}, R{rt}",
        0b1001: f"CONST R{rd}, #{imm8}",
        0b1111: "RET",
    }
    return opcodes.get(opcode, f"??? {instruction:016b}")


def print_program(program):
    """打印程序的汇编形式"""
    for i, inst in enumerate(program):
        print(f"{i:3d}: {inst:016b}  {disassemble(inst)}")

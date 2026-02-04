# Tiny-GPU 指令集架构 (ISA)

## 16-bit 指令格式

| Bits | [15:12] | [11:8] | [7:4] | [3:0] |
|------|---------|--------|-------|-------|
| 字段 | Opcode | Rd/nzp | Rs | Rt/imm[3:0] |

---

## 指令编码表

| 助记符 | 语义 | 编码 |
|--------|------|------|
| **NOP** | `PC = PC + 1` | `0000 xxxx xxxx xxxx` |
| **BRnzp** | `NZP ? PC = IMM8` | `0001 nzp0 iiii iiii` |
| **CMP** | `NZP = sign(Rs - Rt)` | `0010 xxxx ssss tttt` |
| **ADD** | `Rd = Rs + Rt` | `0011 dddd ssss tttt` |
| **SUB** | `Rd = Rs - Rt` | `0100 dddd ssss tttt` |
| **MUL** | `Rd = Rs * Rt` | `0101 dddd ssss tttt` |
| **DIV** | `Rd = Rs / Rt` | `0110 dddd ssss tttt` |
| **LDR** | `Rd = global_data_mem[Rs]` | `0111 dddd ssss xxxx` |
| **STR** | `global_data_mem[Rs] = Rt` | `1000 xxxx ssss tttt` |
| **CONST** | `Rd = IMM8` | `1001 dddd iiii iiii` |
| **JMP** | `PC = Rs` | `1010 xxxx ssss xxxx` |
| **RET** | `done` | `1111 xxxx xxxx xxxx` |

---

## 字段说明

| 符号 | 含义 |
|------|------|
| `dddd` | 目标寄存器 Rd (4 bits) |
| `ssss` | 源寄存器 Rs (4 bits) |
| `tttt` | 源寄存器 Rt (4 bits) |
| `iiii iiii` | 8-bit 立即数 IMM8 |
| `nzp` | 分支条件: n=负, z=零, p=正 |
| `xxxx` | 无关位 (可为任意值) |

---

## 寄存器映射

| 编号 | 名称 | 说明 |
|------|------|------|
| 0-12 | R0-R12 | 通用寄存器 (读写) |
| 13 | %blockIdx | Block 索引 (只读) |
| 14 | %blockDim | Block 大小 (只读) |
| 15 | %threadIdx | Thread 索引 (只读) |

---

## Python 编码辅助函数

```python
def NOP():
    return 0b0000_0000_0000_0000

def BRnzp(nzp, imm8):
    """nzp: 3-bit condition, imm8: target PC"""
    return (0b0001 << 12) | (nzp << 9) | (imm8 & 0xFF)

def BRn(imm8):  return BRnzp(0b100, imm8)
def BRz(imm8):  return BRnzp(0b010, imm8)
def BRp(imm8):  return BRnzp(0b001, imm8)
def BR(imm8):   return BRnzp(0b111, imm8)  # 无条件跳转

def CMP(rs, rt):
    return (0b0010 << 12) | (rs << 4) | rt

def ADD(rd, rs, rt):
    return (0b0011 << 12) | (rd << 8) | (rs << 4) | rt

def SUB(rd, rs, rt):
    return (0b0100 << 12) | (rd << 8) | (rs << 4) | rt

def MUL(rd, rs, rt):
    return (0b0101 << 12) | (rd << 8) | (rs << 4) | rt

def DIV(rd, rs, rt):
    return (0b0110 << 12) | (rd << 8) | (rs << 4) | rt

def LDR(rd, rs):
    return (0b0111 << 12) | (rd << 8) | (rs << 4)

def STR(rs, rt):
    return (0b1000 << 12) | (rs << 4) | rt

def CONST(rd, imm8):
    return (0b1001 << 12) | (rd << 8) | (imm8 & 0xFF)

def RET():
    return 0b1111_0000_0000_0000

# 特殊寄存器别名
R0, R1, R2, R3, R4, R5, R6, R7 = 0, 1, 2, 3, 4, 5, 6, 7
R8, R9, R10, R11, R12 = 8, 9, 10, 11, 12
BLOCK_IDX = 13   # %blockIdx
BLOCK_DIM = 14   # %blockDim
THREAD_IDX = 15  # %threadIdx
```

---

## 示例：matadd 程序

```python
program = [
    MUL(R0, BLOCK_IDX, BLOCK_DIM),  # R0 = blockIdx * blockDim
    ADD(R0, R0, THREAD_IDX),         # R0 += threadIdx -> i
    CONST(R1, 0),                    # baseA = 0
    CONST(R2, 8),                    # baseB = 8
    CONST(R3, 16),                   # baseC = 16
    ADD(R4, R1, R0),                 # addr(A[i])
    LDR(R4, R4),                     # load A[i]
    ADD(R5, R2, R0),                 # addr(B[i])
    LDR(R5, R5),                     # load B[i]
    ADD(R6, R4, R5),                 # C[i] = A[i] + B[i]
    ADD(R7, R3, R0),                 # addr(C[i])
    STR(R7, R6),                     # store C[i]
    RET(),
]
```

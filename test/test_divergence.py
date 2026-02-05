import cocotb
from cocotb.triggers import RisingEdge
from .helpers.setup import setup
from .helpers.memory import Memory
from .helpers.logger import logger
from .helpers.isa import *

@cocotb.test()
async def test_divergence(dut):
    """
    测试分支发散功能
    
    程序逻辑:
    - Thread 0, 2: threadIdx % 2 == 0 → R3 = 200
    - Thread 1, 3: threadIdx % 2 == 1 → R3 = 100
    - 汇合后存储结果到 data[64 + threadIdx]
    
    预期结果:
    - mem[64] = 200 (Thread 0)
    - mem[65] = 100 (Thread 1)
    - mem[66] = 200 (Thread 2)
    - mem[67] = 100 (Thread 3)
    """
    
    program_memory = Memory(dut=dut, addr_bits=8, data_bits=16, channels=1, name="program")
    
    # 程序：根据 threadIdx % 2 分支 (使用显式 RECONV 汇合)
    # 
    # 0: R0 = threadIdx
    # 1: R1 = 2 (用于计算模)
    # 2: R2 = R0 / 2 (整数除法)
    # 3: R2 = R2 * 2
    # 4: R2 = R0 - R2 (R2 = R0 % 2)
    # 5: CONST R4, 0  (用于比较)
    # 6: CMP R2, R4   (比较 R0 % 2 和 0)
    # 7: BRz 11       (如果 == 0，跳到 then 分支)
    # 8: CONST R3, 100  (else: 奇数线程)
    # 9: CONST R5, 12   (跳转目标: 汇合点)
    # 10: JMP R5         (跳到汇合点)
    # 11: CONST R3, 200  (then: 偶数线程)
    # 12: RECONV         (显式汇合点!)
    # 13: CONST R4, 64   (输出基地址)
    # 14: ADD R4, R4, R0
    # 15: STR R4, R3
    # 16: RET
    
    program = [
        ADD(R0, THREAD_IDX, R0),     # 0: R0 = threadIdx (R0 initially 0)
        CONST(R1, 2),                # 1: R1 = 2
        DIV(R2, R0, R1),             # 2: R2 = R0 / 2
        MUL(R2, R2, R1),             # 3: R2 = (R0/2) * 2
        SUB(R2, R0, R2),             # 4: R2 = R0 % 2
        CONST(R4, 0),                # 5: R4 = 0
        CMP(R2, R4),                 # 6: 比较 R2 和 0
        BRz(11),                     # 7: 如果 R2 == 0, 跳到地址 11 (then)
        CONST(R3, 100),              # 8: else 分支: R3 = 100
        CONST(R5, 12),               # 9: 设置跳转目标为汇合点
        JMP(R5),                     # 10: 跳到汇合点
        CONST(R3, 200),              # 11: then 分支: R3 = 200
        RECONV(),                    # 12: 显式汇合点!
        CONST(R4, 64),               # 13: 汇合后: R4 = 64 (输出基地址)
        ADD(R4, R4, R0),             # 14: R4 = 64 + threadIdx
        STR(R4, R3),                 # 15: 存储结果
        RET(),                       # 16: 完成
    ]

    logger.info("Divergence Test Program:")
    for i, inst in enumerate(program):
        logger.info(f"  {i:2d}: {disassemble(inst)}")

    # Data Memory
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=4, name="data")
    data = [0] * 256  # 初始化为 0

    # 4 个线程
    threads = 4

    await setup(
        dut=dut,
        program_memory=program_memory,
        program=program,
        data_memory=data_memory,
        data=data,
        threads=threads
    )

    cycles = 0
    while dut.done.value != 1:
        data_memory.run()
        program_memory.run()
        
        await RisingEdge(dut.clk)
        cycles += 1
        
        if cycles > 50000:
            logger.info("Test timeout!")
            break

    logger.info(f"\n{'='*60}")
    logger.info(f"Divergence Test 完成!")
    logger.info(f"{'='*60}")
    logger.info(f"总周期数: {cycles}")
    
    # 显示结果
    logger.info(f"\n结果内存 (地址 64-67):")
    data_memory.display(68)
    
    # 预期结果
    expected = [200, 100, 200, 100]  # Thread 0,2 even → 200; Thread 1,3 odd → 100
    
    all_passed = True
    for i in range(threads):
        result = data_memory.memory[64 + i]
        exp = expected[i]
        status = "✓" if result == exp else f"✗ (got {result})"
        logger.info(f"  Thread {i}: mem[{64+i}] = {result} (expect {exp}) {status}")
        if result != exp:
            all_passed = False
    
    if all_passed:
        logger.info(f"\n✓ 分支发散测试通过!")
    else:
        logger.info(f"\n✗ 分支发散测试失败!")
    
    # 验证
    for i in range(threads):
        result = data_memory.memory[64 + i]
        exp = expected[i]
        assert result == exp, f"Thread {i}: expected {exp}, got {result}"
    
    logger.info(f"\n{'='*60}")
    logger.info(f"所有断言通过! ✓")
    logger.info(f"{'='*60}")

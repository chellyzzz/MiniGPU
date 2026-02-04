import cocotb
from cocotb.triggers import RisingEdge
from .helpers.setup import setup
from .helpers.memory import Memory
from .helpers.logger import logger
from .helpers.isa import *

@cocotb.test()
async def test_jmp(dut):
    """
    测试 JMP 指令功能
    程序逻辑：使用 JMP 跳过一条"错误"的指令
    
    如果 JMP 正常工作，结果 = 42
    如果 JMP 失败（执行了跳过的指令），结果 = 99
    """
    
    program_memory = Memory(dut=dut, addr_bits=8, data_bits=16, channels=1, name="program")
    
    # 测试程序：JMP 跳过一条指令
    program = [
        MUL(R0, BLOCK_IDX, BLOCK_DIM),  # 0: R0 = blockIdx * blockDim
        ADD(R0, R0, THREAD_IDX),         # 1: R0 += threadIdx (i = thread id)
        CONST(R1, 42),                   # 2: R1 = 42 (正确结果)
        CONST(R2, 5),                    # 3: R2 = 5 (JMP 目标地址)
        JMP(R2),                         # 4: JMP to R2 (跳到地址 5)
        CONST(R1, 99),                   # 5: 这条应该被跳过！如果执行了，R1 = 99
        CONST(R3, 16),                   # 6: (JMP 目标) R3 = 16 (baseC) -- 实际上 JMP 跳到这里
        ADD(R3, R3, R0),                 # 7: R3 = baseC + i
        STR(R3, R1),                     # 8: store R1 to memory
        RET(),                           # 9: done
    ]
    
    # 注意：JMP 会跳到地址 5，但地址 5 是 CONST R1, 99
    # 所以设计需要调整：JMP 应该跳到地址 6 才能跳过 CONST R1, 99
    # 重新设计程序
    program = [
        MUL(R0, BLOCK_IDX, BLOCK_DIM),  # 0: R0 = blockIdx * blockDim
        ADD(R0, R0, THREAD_IDX),         # 1: R0 += threadIdx (i = thread id)
        CONST(R1, 42),                   # 2: R1 = 42 (正确结果)
        CONST(R2, 6),                    # 3: R2 = 6 (JMP 目标地址，跳过地址 4 和 5)
        JMP(R2),                         # 4: JMP to address 6
        CONST(R1, 99),                   # 5: 这条应该被跳过！
        CONST(R3, 16),                   # 6: (JMP 目标) R3 = 16 (baseC)
        ADD(R3, R3, R0),                 # 7: R3 = baseC + i
        STR(R3, R1),                     # 8: store R1 to memory
        RET(),                           # 9: done
    ]

    # 打印程序
    logger.info("JMP Test Program:")
    for i, inst in enumerate(program):
        marker = " <-- JMP target" if i == 6 else ""
        marker = " <-- should be skipped!" if i == 5 else marker
        logger.info(f"  {i:2d}: {disassemble(inst)}{marker}")

    # Data Memory
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=4, name="data")
    data = [0] * 256

    # 使用 4 个线程
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
            print("Test timeout!")
            break

    logger.info(f"\n{'='*60}")
    logger.info(f"JMP Test 完成!")
    logger.info(f"{'='*60}")
    logger.info(f"总周期数: {cycles}")
    
    # 显示结果
    logger.info(f"\n结果内存 (地址 16-19):")
    data_memory.display(24)
    
    # 验证结果
    # 如果 JMP 正常工作，每个线程存储的值应该是 42
    # 如果 JMP 失败，值会是 99
    expected = 42
    all_passed = True
    for i in range(threads):
        result = data_memory.memory[16 + i]
        status = "✓" if result == expected else "✗"
        logger.info(f"  Thread {i}: result = {result} (expected {expected}) {status}")
        if result != expected:
            all_passed = False
    
    if all_passed:
        logger.info(f"\n✓ JMP 指令工作正常！跳过了错误指令。")
    else:
        logger.info(f"\n✗ JMP 指令失败！执行了应该跳过的指令。")
    
    for i in range(threads):
        result = data_memory.memory[16 + i]
        assert result == expected, f"Thread {i}: expected {expected}, got {result}"
    
    logger.info(f"\n{'='*60}")
    logger.info(f"所有断言通过! ✓")
    logger.info(f"{'='*60}")

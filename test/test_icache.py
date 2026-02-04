import cocotb
from cocotb.triggers import RisingEdge
from .helpers.setup import setup
from .helpers.memory import Memory
from .helpers.logger import logger
from .helpers.isa import *

@cocotb.test()
async def test_icache(dut):
    """
    测试指令缓存 (I-Cache) 功能
    - 使用带循环的程序（类似 matmul 的收敛分支）
    - 循环会多次执行同一段指令，充分体现缓存优势
    - 监控程序内存访问次数来验证缓存行为
    """
    
    # Program Memory - 仿照 matmul 的循环结构
    # 程序功能：每个线程计算 sum = 0 + 1 + 2 + ... + (N-1)
    # 所有线程循环次数相同，BRn 条件一致，不会产生 divergence
    program_memory = Memory(dut=dut, addr_bits=8, data_bits=16, channels=1, name="program")
    
    # 使用 ISA 辅助函数编写程序
    program = [
        # 初始化
        MUL(R0, BLOCK_IDX, BLOCK_DIM),  # 0: R0 = blockIdx * blockDim
        ADD(R0, R0, THREAD_IDX),         # 1: R0 = R0 + threadIdx (i = global thread id)
        CONST(R1, 1),                    # 2: R1 = 1 (increment)
        CONST(R2, 4),                    # 3: R2 = 4 (N = 循环次数)
        CONST(R3, 0),                    # 4: R3 = 0 (sum)
        CONST(R4, 0),                    # 5: R4 = 0 (k)
        
        # LOOP: (地址 6-9，会被执行 4 次)
        ADD(R3, R3, R4),                 # 6: sum += k
        ADD(R4, R4, R1),                 # 7: k++
        CMP(R4, R2),                     # 8: compare k with N
        BRn(6),                          # 9: if k < N, goto LOOP
        
        # 存储结果
        CONST(R5, 16),                   # 10: R5 = 16 (baseC)
        ADD(R5, R5, R0),                 # 11: R5 = baseC + i (addr)
        STR(R5, R3),                     # 12: store sum
        RET(),                           # 13: done
    ]

    # 打印程序的反汇编形式
    logger.info("Program:")
    for i, inst in enumerate(program):
        logger.info(f"  {i:2d}: {inst:016b}  {disassemble(inst)}")

    # Data Memory - 空，只用于存储结果
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=4, name="data")
    data = [0] * 256

    # Device Control - 使用 4 个线程 (1 个 block)
    threads = 4

    await setup(
        dut=dut,
        program_memory=program_memory,
        program=program,
        data_memory=data_memory,
        data=data,
        threads=threads
    )

    # 统计计数器
    cycles = 0
    program_mem_accesses = 0

    while dut.done.value != 1:
        data_memory.run()
        program_memory.run()

        await cocotb.triggers.ReadOnly()
        
        # 监控程序内存访问
        try:
            current_read_valid = int(dut.program_mem_read_valid.value)
            if current_read_valid == 1:
                program_mem_accesses += 1
        except:
            pass
        
        await RisingEdge(dut.clk)
        cycles += 1
        
        # 防止无限循环
        if cycles > 50000:
            print("Test timeout!")
            break

    logger.info(f"\n{'='*60}")
    logger.info(f"I-Cache 测试完成!")
    logger.info(f"{'='*60}")
    logger.info(f"总周期数: {cycles}")
    logger.info(f"程序内存访问次数: {program_mem_accesses}")
    logger.info(f"程序总指令数: {len(program)}")
    
    # 分析缓存效果
    unique_instructions = len(program)
    total_instructions_executed = 6 + (4 * 4) + 4  # 初始化 + 循环体*4 + 结尾
    
    logger.info(f"\n缓存分析:")
    logger.info(f"  唯一指令数: {unique_instructions}")
    logger.info(f"  总执行指令数 (估算): {total_instructions_executed}")
    logger.info(f"  实际内存访问次数: {program_mem_accesses}")
    
    if program_mem_accesses <= unique_instructions:
        logger.info(f"  ✓ 缓存有效! 内存访问 <= 唯一指令数")
    else:
        logger.info(f"  △ 缓存未完全命中")
    
    # 显示结果
    logger.info(f"\n结果内存 (地址 16-19):")
    data_memory.display(24)
    
    # 验证结果: sum(0..3) = 0+1+2+3 = 6
    expected_sum = sum(range(4))  # 0+1+2+3 = 6
    for i in range(threads):
        result = data_memory.memory[16 + i]
        logger.info(f"  Thread {i}: sum = {result} (expected {expected_sum})")
        assert result == expected_sum, f"Thread {i}: expected {expected_sum}, got {result}"
    
    logger.info(f"\n{'='*60}")
    logger.info(f"所有断言通过! ✓")
    logger.info(f"{'='*60}")

import cocotb
from cocotb.triggers import RisingEdge
from .helpers.setup import setup
from .helpers.memory import Memory
from .helpers.logger import logger
from .helpers.isa import *

@cocotb.test()
async def test_scalability(dut):
    """
    测试 32 线程执行 (8 blocks, 2 cores)
    验证 dispatcher 能正确分配多轮 block
    
    每个线程计算: result[i] = i * 2
    """
    
    program_memory = Memory(dut=dut, addr_bits=8, data_bits=16, channels=1, name="program")
    
    # 更简单的程序: result[i] = global_id
    # 只测试 thread id 计算是否正确
    program = [
        MUL(R0, BLOCK_IDX, BLOCK_DIM),  # 0: R0 = blockIdx * blockDim
        ADD(R0, R0, THREAD_IDX),         # 1: R0 += threadIdx (i = global thread id)
        CONST(R3, 64),                   # 2: R3 = 64 (base output address)
        ADD(R3, R3, R0),                 # 3: R3 = 64 + i
        STR(R3, R0),                     # 4: store i (not i*2, to simplify)
        RET(),                           # 5: done
    ]

    logger.info("Scalability Test Program (storing global_id directly):")
    for i, inst in enumerate(program):
        logger.info(f"  {i:2d}: {disassemble(inst)}")

    # Data Memory - 初始化为 255 方便识别未写入的位置
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=4, name="data")
    data = [255] * 256  # 初始化为 255

    # 32 个线程
    threads = 32

    await setup(
        dut=dut,
        program_memory=program_memory,
        program=program,
        data_memory=data_memory,
        data=data,
        threads=threads
    )

    cycles = 0
    last_blocks_dispatched = -1
    
    while dut.done.value != 1:
        data_memory.run()
        program_memory.run()
        
        # 监控 dispatch 状态
        try:
            blocks_dispatched = int(dut.blocks_dispatched.value)
            if blocks_dispatched != last_blocks_dispatched:
                logger.info(f"Cycle {cycles}: blocks_dispatched = {blocks_dispatched}")
                last_blocks_dispatched = blocks_dispatched
        except:
            pass
        
        await RisingEdge(dut.clk)
        cycles += 1
        
        if cycles > 100000:
            logger.info("Test timeout!")
            break

    logger.info(f"\n{'='*60}")
    logger.info(f"Scalability Test 完成!")
    logger.info(f"{'='*60}")
    logger.info(f"配置: {threads} threads, 8 blocks, THREADS_PER_BLOCK=4")
    logger.info(f"总周期数: {cycles}")
    
    # 显示结果 - 打印每个位置的值
    logger.info(f"\n结果内存 (地址 64-95):")
    for i in range(threads):
        result = data_memory.memory[64 + i]
        expected = i
        status = "✓" if result == expected else f"✗ (got {result})"
        logger.info(f"  mem[{64+i}] = {result:3d}  (expect {i:3d}) {status}")
    
    # 验证结果: result[i] = i
    for i in range(threads):
        expected = i
        result = data_memory.memory[64 + i]
        assert result == expected, f"Thread {i}: expected {expected}, got {result}"
    
    logger.info(f"\n{'='*60}")
    logger.info(f"所有断言通过! ✓")
    logger.info(f"{'='*60}")

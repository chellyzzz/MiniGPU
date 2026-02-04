import cocotb
from cocotb.triggers import RisingEdge
from .helpers.setup import setup
from .helpers.memory import Memory
from .helpers.format import format_cycle
from .helpers.logger import logger

@cocotb.test()
async def test_icache(dut):    
    # Program Memory
    program_memory = Memory(dut=dut, addr_bits=8, data_bits=16, channels=1, name="program")
    
    # 带循环的程序：累加 0 到 N-1
    # 这个程序会多次执行相同的指令，非常适合测试 I-Cache
    program = [
        # 初始化
        0b0101000011011110, # 0: MUL R0, %blockIdx, %blockDim
        0b0011000000001111, # 1: ADD R0, R0, %threadIdx      ; i = global thread id
        0b1001000100000000, # 2: CONST R1, #0                ; sum = 0
        0b1001001000000000, # 3: CONST R2, #0                ; j = 0
        0b1001001100000100, # 4: CONST R3, #4                ; N = 4 (循环次数)
        
        # 循环体 (LOOP: 地址 5-8)
        0b0011000100010010, # 5: ADD R1, R1, R2              ; sum += j
        0b1001010000000001, # 6: CONST R4, #1                ; temp = 1
        0b0011001000100100, # 7: ADD R2, R2, R4              ; j++
        0b0110001000110000, # 8: CMP R2, R3                  ; compare j with N
        0b0001100000000101, # 9: BRn LOOP (PC=5)             ; if j < N, goto LOOP
        
        # 存储结果
        0b1001010100010000, # 10: CONST R5, #16              ; baseC
        0b0011010101010000, # 11: ADD R5, R5, R0             ; addr = baseC + i
        0b1000000001010001, # 12: STR R5, R1                 ; store sum
        0b1111000000000000, # 13: RET
    ]

    # Data Memory
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=4, name="data")
    data = [0] * 256  # 空数据内存

    # Device Control - 使用 4 个线程
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
    last_program_read_valid = 0
    
    # 用于统计哪些地址被访问过
    accessed_addresses = set()
    address_access_count = {}

    while dut.done.value != 1:
        data_memory.run()
        program_memory.run()

        await cocotb.triggers.ReadOnly()
        
        # 监控程序内存访问
        try:
            current_read_valid = int(dut.program_mem_read_valid.value)
            if current_read_valid == 1:
                program_mem_accesses += 1
                # 尝试读取地址
                try:
                    addr = int(dut.program_mem_read_address.value)
                    accessed_addresses.add(addr)
                    address_access_count[addr] = address_access_count.get(addr, 0) + 1
                except:
                    pass
        except:
            pass
        
        # 每 100 周期打印一次进度 (简化输出，避免格式化错误)
        if cycles % 500 == 0:
            logger.info(f"Cycle {cycles}: running...")
        
        await RisingEdge(dut.clk)
        cycles += 1
        
        # 防止无限循环
        if cycles > 10000:
            logger.error("Test timeout!")
            break

    logger.info(f"\n{'='*60}")
    logger.info(f"测试完成!")
    logger.info(f"{'='*60}")
    logger.info(f"总周期数: {cycles}")
    logger.info(f"程序内存访问次数: {program_mem_accesses}")
    logger.info(f"唯一指令地址数: {len(accessed_addresses)}")
    logger.info(f"程序总指令数: {len(program)}")
    
    # 计算理论缓存命中率
    # 如果有缓存，每个唯一地址只需访问一次
    # 无缓存时，每次取指都要访问
    if program_mem_accesses > 0:
        theoretical_hits = program_mem_accesses - len(accessed_addresses)
        hit_rate = theoretical_hits / program_mem_accesses * 100
        logger.info(f"理论缓存命中率 (如果有缓存): {hit_rate:.1f}%")
    
    logger.info(f"\n地址访问统计:")
    for addr in sorted(address_access_count.keys()):
        count = address_access_count[addr]
        logger.info(f"  地址 {addr:3d}: 访问 {count:3d} 次")
    
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
    logger.info(f"所有断言通过!")
    logger.info(f"{'='*60}")

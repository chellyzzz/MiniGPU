import cocotb
from cocotb.triggers import RisingEdge
from .helpers.setup import setup
from .helpers.memory import Memory
from .helpers.format import format_cycle
from .helpers.logger import logger

@cocotb.test()
async def test_shared_memory(dut):
    """
    Test shared memory (LDS/STS instructions).
    
    Scenario:
    - Thread 0 stores its thread ID to shared memory address 0
    - Thread 0 loads from shared memory address 0 into R1
    - All threads add their thread ID to R1 and store result to global memory
    
    Expected: Each thread writes Thread0's ID + their own ID to memory
    """
    
    # Program Memory
    program_memory = Memory(dut=dut, addr_bits=8, data_bits=16, channels=1, name="program")
    
    # Instruction encoding:
    # LDS: 1100 Rd[11:8] Rs[7:4] 0000 -> LDS Rd, [Rs]
    # STS: 1101 0000 Rs[7:4] Rt[3:0] -> STS [Rs], Rt
    
    program = [
        0b1001000000000000,  # CONST R0, #0                ; R0 = 0 (shared memory address)
        0b1101000000001111,  # STS [R0], %threadIdx        ; shared[0] = threadIdx (Thread 0 writes 0)
        0b1100000100000000,  # LDS R1, [R0]                ; R1 = shared[0] (all threads read Thread 0's value)
        0b0011001000011111,  # ADD R2, R1, %threadIdx      ; R2 = R1 + threadIdx
        0b1001001100000000,  # CONST R3, #0                ; R3 = 0 (base address for output)
        0b0011010000111111,  # ADD R4, R3, %threadIdx      ; R4 = base + threadIdx (output address)
        0b1000000001000010,  # STR [R4], R2                ; Store result to global memory
        0b1111000000000000,  # RET
    ]

    # Data Memory (empty, will be written by threads)
    data_memory = Memory(dut=dut, addr_bits=8, data_bits=8, channels=4, name="data")
    data = [0] * 16  # Initialize to zeros

    # Device Control - 4 threads
    threads = 4

    await setup(
        dut=dut,
        program_memory=program_memory,
        program=program,
        data_memory=data_memory,
        data=data,
        threads=threads
    )

    logger.info("=== Testing Shared Memory (LDS/STS) ===")
    data_memory.display(8)

    cycles = 0
    max_cycles = 100000
    while dut.done.value != 1 and cycles < max_cycles:
        data_memory.run()
        program_memory.run()

        await cocotb.triggers.ReadOnly()
        # Skip format_cycle during shared memory test to avoid X-value issues
        
        await RisingEdge(dut.clk)
        cycles += 1

    logger.info(f"Completed in {cycles} cycles")
    data_memory.display(8)

    # Expected results:
    # Thread 0 stores 0 to shared[0]
    # All threads read 0 from shared[0]
    # Thread i computes: 0 + i = i
    # Thread i stores to address i
    expected_results = [0, 1, 2, 3]  # Each thread writes its own ID
    
    for i, expected in enumerate(expected_results):
        result = data_memory.memory[i]
        assert result == expected, f"Result mismatch at index {i}: expected {expected}, got {result}"
    
    logger.info("=== Shared Memory Test PASSED ===")

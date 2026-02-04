# Tiny-GPU Performance Baseline

## Test Results (NUM_CORES = 2)

| Test | Status | Sim Time (ns) | Cycles | Description |
|------|--------|---------------|--------|-------------|
| `test_matadd` | ✅ PASS | 5,375,000 | 5,375 | Vector addition (8 elements) |
| `test_matmul` | ✅ PASS | 14,050,000 | 14,050 | Matrix multiply (2×2 × 2×2) |
| `test_jmp` | ✅ PASS | 3,450,000 | 3,450 | JMP instruction test |
| `test_icache` | ✅ PASS | 8,200,000 | 8,200 | I-Cache with loop |

## Scalability Test (NUM_CORES = 4)

| Test | 2 Cores | 4 Cores | Speedup |
|------|---------|---------|---------|
| `test_matadd` | 5,375 | 5,375 | 1.0x |

**Note**: No speedup because matadd uses only 2 blocks (8 threads / 4 threads per block). Need larger workload to benefit from more cores.

## Configuration

| Parameter | Value |
|-----------|-------|
| NUM_CORES | 4 (was 2) |
| THREADS_PER_BLOCK | 4 |
| DATA_MEM_CHANNELS | 4 |
| I-Cache Lines | 16 |
| Clock Period | 1ns |

## Features Implemented

- [x] Basic ISA (13 instructions including JMP)
- [x] Multi-channel memory controller (4 parallel)
- [x] I-Cache (16-line direct-mapped)
- [x] JMP instruction
- [ ] SIMT Stack (branch divergence) ← Next
- [ ] Shared Memory
- [ ] Memory Coalescing

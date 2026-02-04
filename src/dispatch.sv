`default_nettype none
`timescale 1ns/1ns

// BLOCK DISPATCH
// > The GPU has one dispatch unit at the top level
// > Manages processing of threads and marks kernel execution as done
// > Sends off batches of threads in blocks to be executed by available compute cores
module dispatch #(
    parameter NUM_CORES = 2,
    parameter THREADS_PER_BLOCK = 4
) (
    input wire clk,
    input wire reset,
    input wire start,

    // Kernel Metadata
    input wire [7:0] thread_count,

    // Core States
    input wire [NUM_CORES-1:0] core_done,
    output reg [NUM_CORES-1:0] core_start,
    output reg [NUM_CORES-1:0] core_reset,
    output reg [7:0] core_block_id [NUM_CORES-1:0],
    output reg [$clog2(THREADS_PER_BLOCK):0] core_thread_count [NUM_CORES-1:0],

    // Kernel Execution
    output reg done
);
    // Calculate the total number of blocks based on total threads & threads per block
    wire [7:0] total_blocks;
    assign total_blocks = (thread_count + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK;

    // Keep track of how many blocks have been processed
    reg [7:0] blocks_dispatched;
    reg [7:0] blocks_done;
    reg start_execution;

    integer i;
    
    // Combinational: count how many cores are completing this cycle
    reg [7:0] cores_completing;
    always @(*) begin
        cores_completing = 0;
        for (i = 0; i < NUM_CORES; i = i + 1) begin
            if (core_start[i] && core_done[i]) begin
                cores_completing = cores_completing + 1;
            end
        end
    end
    
    // Combinational: determine dispatch decisions for each core
    // should_dispatch[i] = 1 means core i should start a new block
    // dispatch_block_id[i] = the block ID to assign to core i
    reg [NUM_CORES-1:0] should_dispatch;
    reg [7:0] dispatch_block_id [NUM_CORES-1:0];
    reg [7:0] total_dispatching;
    
    always @(*) begin
        total_dispatching = 0;
        for (i = 0; i < NUM_CORES; i = i + 1) begin
            should_dispatch[i] = 0;
            dispatch_block_id[i] = 0;
            
            if (core_reset[i] && !core_start[i] && ((blocks_dispatched + total_dispatching) < total_blocks)) begin
                should_dispatch[i] = 1;
                dispatch_block_id[i] = blocks_dispatched + total_dispatching;
                total_dispatching = total_dispatching + 1;
            end
        end
    end

    // Sequential logic: update state on clock edge (only non-blocking assignments)
    always @(posedge clk) begin
        if (reset) begin
            done <= 1'b0;
            blocks_dispatched <= 8'b0;
            blocks_done <= 8'b0;
            start_execution <= 1'b0;

            for (i = 0; i < NUM_CORES; i = i + 1) begin
                core_start[i] <= 1'b0;
                core_reset[i] <= 1'b1;
                core_block_id[i] <= 8'b0;
                core_thread_count[i] <= THREADS_PER_BLOCK;
            end
        end else if (start) begin
            // Initialize on first start
            if (!start_execution) begin
                start_execution <= 1'b1;
            end

            // Update counters atomically
            blocks_done <= blocks_done + cores_completing;
            blocks_dispatched <= blocks_dispatched + total_dispatching;
            
            // Process each core
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                if (should_dispatch[i]) begin
                    // Dispatch a new block to this core
                    core_reset[i] <= 1'b0;
                    core_start[i] <= 1'b1;
                    core_block_id[i] <= dispatch_block_id[i];
                    
                    // Calculate thread count for this block
                    if (dispatch_block_id[i] == total_blocks - 1) begin
                        core_thread_count[i] <= thread_count - (dispatch_block_id[i] * THREADS_PER_BLOCK);
                    end else begin
                        core_thread_count[i] <= THREADS_PER_BLOCK;
                    end
                end
                else if (core_start[i] && core_done[i]) begin
                    // Core finished, reset for next block
                    core_reset[i] <= 1'b1;
                    core_start[i] <= 1'b0;
                end
            end
            
            // Check if all blocks are done
            if ((blocks_done + cores_completing) >= total_blocks && total_blocks > 0) begin
                done <= 1'b1;
            end
        end
    end
endmodule
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

    // Next state signals for blocks_dispatched and blocks_done
    reg [7:0] next_blocks_dispatched;
    reg [7:0] next_blocks_done;

    // Per-core control signals
    reg [NUM_CORES-1:0] should_dispatch;
    reg [NUM_CORES-1:0] should_complete;

    integer i;

    // Combinational logic: determine which cores need dispatching or completion
    always @(*) begin
        next_blocks_dispatched = blocks_dispatched;
        next_blocks_done = blocks_done;
        
        for (i = 0; i < NUM_CORES; i = i + 1) begin
            should_dispatch[i] = 1'b0;
            should_complete[i] = 1'b0;
        end

        // Check for dispatch opportunities
        for (i = 0; i < NUM_CORES; i = i + 1) begin
            if (core_reset[i] && (next_blocks_dispatched < total_blocks)) begin
                should_dispatch[i] = 1'b1;
                next_blocks_dispatched = next_blocks_dispatched + 1;
            end
        end

        // Check for completion
        for (i = 0; i < NUM_CORES; i = i + 1) begin
            if (core_start[i] && core_done[i]) begin
                should_complete[i] = 1'b1;
                next_blocks_done = next_blocks_done + 1;
            end
        end
    end

    // Sequential logic: update state on clock edge
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
                for (i = 0; i < NUM_CORES; i = i + 1) begin
                    core_reset[i] <= 1'b1;
                end
            end

            // Check if all blocks are done
            if (next_blocks_done == total_blocks) begin
                done <= 1'b1;
            end

            // Update counters
            blocks_dispatched <= next_blocks_dispatched;
            blocks_done <= next_blocks_done;

            // Dispatch new blocks to cores
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                if (should_dispatch[i]) begin
                    core_reset[i] <= 1'b0;
                    core_start[i] <= 1'b1;
                    core_block_id[i] <= blocks_dispatched + i[7:0];
                    
                    // Calculate thread count for this block
                    if ((blocks_dispatched + i) == total_blocks - 1) begin
                        core_thread_count[i] <= thread_count - ((blocks_dispatched + i[7:0]) * THREADS_PER_BLOCK);
                    end else begin
                        core_thread_count[i] <= THREADS_PER_BLOCK;
                    end
                end
            end

            // Handle core completion
            for (i = 0; i < NUM_CORES; i = i + 1) begin
                if (should_complete[i]) begin
                    core_reset[i] <= 1'b1;
                    core_start[i] <= 1'b0;
                end
            end
        end
    end
endmodule
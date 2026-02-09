`default_nettype none
`timescale 1ns/1ns

// SHARED MEMORY (Scratchpad)
// > Block-level shared memory accessible by all threads
// > Enables inter-thread communication within a block
// > Single-cycle access latency
module shared_memory #(
    parameter ADDR_BITS = 8,
    parameter DATA_BITS = 8,
    parameter SIZE = 256,  // bytes
    parameter THREADS_PER_BLOCK = 4
) (
    input wire clk,
    input wire reset,
    
    // Read port (active thread reads)
    input wire read_enable,
    input wire [ADDR_BITS-1:0] read_addr,
    output reg [DATA_BITS-1:0] read_data,
    
    // Write port (active thread writes)
    input wire write_enable,
    input wire [ADDR_BITS-1:0] write_addr,
    input wire [DATA_BITS-1:0] write_data
);

    // Memory array
    reg [DATA_BITS-1:0] mem [SIZE-1:0];
    
    integer i;
    
    always @(posedge clk) begin
        if (reset) begin
            // Initialize to zero
            for (i = 0; i < SIZE; i = i + 1) begin
                mem[i] <= 0;
            end
            read_data <= 0;
        end else begin
            // Write (priority over read to same address)
            if (write_enable) begin
                mem[write_addr] <= write_data;
            end
            
            // Read (synchronous, 1-cycle latency)
            if (read_enable) begin
                read_data <= mem[read_addr];
            end
        end
    end

endmodule

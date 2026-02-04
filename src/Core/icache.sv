`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION CACHE
// > Simple 16-line direct-mapped cache for program instructions
// > Reduces program memory access latency on cache hits
module icache #(
    parameter CACHE_LINES = 16,
    parameter ADDR_BITS = 8,
    parameter DATA_BITS = 16
) (
    input  wire clk,
    input  wire reset,
    
    // Fetcher interface
    input  wire                  fetch_valid,
    input  wire [ADDR_BITS-1:0]  fetch_pc,
    output reg                   fetch_ready,
    output reg  [DATA_BITS-1:0]  fetch_instruction,
    
    // Program memory interface (for cache miss)
    output reg                   mem_read_valid,
    output reg  [ADDR_BITS-1:0]  mem_read_address,
    input  wire                  mem_read_ready,
    input  wire [DATA_BITS-1:0]  mem_read_data
);

// State definitions
localparam IDLE  = 2'b00;
localparam CHECK = 2'b01;
localparam FETCH = 2'b10;

reg [1:0] state;

// Cache storage
reg [DATA_BITS-1:0] cache_data  [CACHE_LINES-1:0];
reg [3:0]           cache_tag   [CACHE_LINES-1:0];
reg                 cache_valid [CACHE_LINES-1:0];

wire [3:0] index = fetch_pc[3:0];
wire [3:0] tag   = fetch_pc[7:4];

wire hit = cache_valid[index] && (cache_tag[index] == tag); // Cache state machine
integer i;

always @(posedge clk) begin
    if (reset) begin
        state <= IDLE;
        fetch_ready <= 0;
        fetch_instruction <= 0;
        mem_read_valid <= 0;
        mem_read_address <= 0;
        // Invalidate all cache lines
        for (i = 0; i < CACHE_LINES; i = i + 1) begin
            cache_valid[i] <= 0;
            cache_tag[i] <= 0;
            cache_data[i] <= 0;
        end
    end else begin
        // Default: clear ready signal
        fetch_ready <= 0;
        
        case (state)
            IDLE: begin
                if (fetch_valid) begin
                    state <= CHECK;
                end
            end
    
            CHECK: begin
                if (hit) begin
                    fetch_instruction <= cache_data[index];
                    fetch_ready <= 1;
                    state <= IDLE;
                end else begin
                    mem_read_valid <= 1;
                    mem_read_address <= fetch_pc;
                    state <= FETCH; 
                end
            end
    
            FETCH: begin
                if (mem_read_ready) begin
                    // Fill cache line
                    cache_data[index] <= mem_read_data;
                    cache_tag[index] <= tag;
                    cache_valid[index] <= 1;
                    fetch_instruction <= mem_read_data;
                    fetch_ready <= 1;
                    mem_read_valid <= 0;
                    state <= IDLE;
                end
            end
            
            default: state <= IDLE;
        endcase
    end
end

endmodule
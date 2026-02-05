`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION FETCHER
// > Retrieves the instruction at the current PC from global program memory
// > Integrates with I-Cache for reduced latency on cache hits
// > Each core has its own fetcher
module fetcher #(
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16
) (
    input wire clk,
    input wire reset,
    
    // Execution State
    input wire [2:0] core_state,
    input wire [7:0] current_pc,

    // Program Memory Interface
    output wire mem_read_valid,
    output wire [PROGRAM_MEM_ADDR_BITS-1:0] mem_read_address,
    input wire mem_read_ready,
    input wire [PROGRAM_MEM_DATA_BITS-1:0] mem_read_data,

    // Fetcher Output
    output reg [2:0] fetcher_state,
    output reg [PROGRAM_MEM_DATA_BITS-1:0] instruction
);

    localparam IDLE     = 3'b000;
    localparam FETCHING = 3'b001;
    localparam FETCHED  = 3'b010;
    
    // Internal signals for I-Cache
    reg cache_request;
    wire cache_ready;
    wire [PROGRAM_MEM_DATA_BITS-1:0] cache_instruction;
    
    // I-Cache instance
    icache #(
        .CACHE_LINES(16),
        .ADDR_BITS(PROGRAM_MEM_ADDR_BITS),
        .DATA_BITS(PROGRAM_MEM_DATA_BITS)
    ) icache_inst (
        .clk(clk),
        .reset(reset),
        .fetch_valid(cache_request),
        .fetch_pc(current_pc),
        .fetch_ready(cache_ready),
        .fetch_instruction(cache_instruction),
        .mem_read_valid(mem_read_valid),
        .mem_read_address(mem_read_address),
        .mem_read_ready(mem_read_ready),
        .mem_read_data(mem_read_data)
    );
    
    always @(posedge clk) begin
        if (reset) begin
            fetcher_state <= IDLE;
            cache_request <= 0;
            instruction <= {PROGRAM_MEM_DATA_BITS{1'b0}};
        end else begin
            case (fetcher_state)
                IDLE: begin
                    // Start fetching when core_state = FETCH (3'b001)
                    if (core_state == 3'b001) begin
                        fetcher_state <= FETCHING;
                        cache_request <= 1;
                    end
                end
                
                FETCHING: begin
                    // Wait for cache response (hit or miss filled)
                    cache_request <= 0;  // Only pulse for 1 cycle
                    if (cache_ready) begin
                        fetcher_state <= FETCHED;
                        instruction <= cache_instruction;
                    end
                end
                
                FETCHED: begin
                    // Reset when core moves to DECODE state (3'b010)
                    if (core_state == 3'b010) begin 
                        fetcher_state <= IDLE;
                    end
                end
                
                default: fetcher_state <= IDLE;
            endcase
        end
    end

endmodule

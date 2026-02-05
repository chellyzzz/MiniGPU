`default_nettype none
`timescale 1ns/1ns

// SIMT STACK
// > Manages branch divergence and reconvergence within a block
// > Each entry stores: PC, ActiveMask, ReconvPC
// > Push on divergent branch, Pop when PC reaches ReconvPC
module simt_stack #(
    parameter THREADS_PER_BLOCK = 4,
    parameter STACK_DEPTH = 2,
    parameter PC_BITS = 8
) (
    input  wire clk,
    input  wire reset,
    
    // Push/Pop 控制
    input  wire push,
    input  wire pop,
    
    // Push 数据
    input  wire [PC_BITS-1:0]           push_pc,
    input  wire [THREADS_PER_BLOCK-1:0] push_mask,
    input  wire [PC_BITS-1:0]           push_reconvpc,
    
    // 栈顶输出 (Top of Stack)
    output wire [PC_BITS-1:0]           tos_pc,
    output wire [THREADS_PER_BLOCK-1:0] tos_mask,
    output wire [PC_BITS-1:0]           tos_reconvpc,
    
    // 状态
    output wire empty,
    output wire full
);
    // Stack storage
    reg [PC_BITS-1:0]           stack_pc      [STACK_DEPTH-1:0];
    reg [THREADS_PER_BLOCK-1:0] stack_mask    [STACK_DEPTH-1:0];
    reg [PC_BITS-1:0]           stack_reconvpc[STACK_DEPTH-1:0];
    
    // Stack pointer (points to next free slot)
    reg [$clog2(STACK_DEPTH):0] sp;
    
    // Stack status
    assign empty = (sp == 0);
    assign full  = (sp == STACK_DEPTH);
    
    // Top of stack outputs (sp-1 is the current top)
    // When empty, output defaults
    assign tos_pc       = empty ? {PC_BITS{1'b0}}           : stack_pc[sp-1];
    assign tos_mask     = empty ? {THREADS_PER_BLOCK{1'b1}} : stack_mask[sp-1];
    assign tos_reconvpc = empty ? {PC_BITS{1'b1}}           : stack_reconvpc[sp-1];
    
    integer i;
    
    always @(posedge clk) begin
        if (reset) begin
            sp <= 0;
            for (i = 0; i < STACK_DEPTH; i = i + 1) begin
                stack_pc[i]       <= 0;
                stack_mask[i]     <= {THREADS_PER_BLOCK{1'b1}};
                stack_reconvpc[i] <= {PC_BITS{1'b1}};
            end
        end else begin
            // Push takes priority if both push and pop are asserted
            if (push && !full) begin
                stack_pc[sp]       <= push_pc;
                stack_mask[sp]     <= push_mask;
                stack_reconvpc[sp] <= push_reconvpc;
                sp <= sp + 1;
            end else if (pop && !empty) begin
                sp <= sp - 1;
            end
        end
    end
endmodule

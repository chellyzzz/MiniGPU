`default_nettype none
`timescale 1ns/1ns

// SCHEDULER with SIMT Stack
// > Manages the entire control flow of a single compute core processing 1 block
// > Supports branch divergence with SIMT stack for explicit reconvergence (RECONV instruction)
// 1. FETCH - Retrieve instruction at current program counter (PC) from program memory
// 2. DECODE - Decode the instruction into the relevant control signals
// 3. REQUEST - If we have an instruction that accesses memory, trigger the async memory requests from LSUs
// 4. WAIT - Wait for all async memory requests to resolve (if applicable)
// 5. EXECUTE - Execute computations on retrieved data from registers / memory
// 6. UPDATE - Update register values (including NZP register) and program counter
//             Handle branch divergence: push divergent path to stack, continue with taken path
//             Handle reconvergence: pop stack on RECONV instruction
module scheduler #(
    parameter THREADS_PER_BLOCK = 4,
    parameter PROGRAM_MEM_ADDR_BITS = 8
) (
    input wire clk,
    input wire reset,
    input wire start,
    
    // Control Signals
    input reg decoded_mem_read_enable,
    input reg decoded_mem_write_enable,
    input reg decoded_ret,
    input reg [1:0] decoded_pc_mux, // 0=PC+1, 1=BRnzp, 2=JMP
    input reg decoded_reconv,       // Explicit reconvergence instruction

    // Memory Access State
    input reg [2:0] fetcher_state,
    input reg [1:0] lsu_state [THREADS_PER_BLOCK-1:0],

    // Current & Next PC (per-thread next_pc for divergence detection)
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,
    input wire [PROGRAM_MEM_ADDR_BITS-1:0] next_pc [THREADS_PER_BLOCK-1:0],

    // Active Mask (which threads are currently active)
    output reg [THREADS_PER_BLOCK-1:0] active_mask,

    // Execution State
    output reg [2:0] core_state,
    output reg done
);
    localparam IDLE = 3'b000,    // Waiting to start
               FETCH = 3'b001,   // Fetch instructions from program memory
               DECODE = 3'b010,  // Decode instructions into control signals
               REQUEST = 3'b011, // Request data from registers or memory
               WAIT = 3'b100,    // Wait for response from memory if necessary
               EXECUTE = 3'b101, // Execute ALU and PC calculations
               UPDATE = 3'b110,  // Update registers, NZP, and PC
               DONE = 3'b111;    // Done executing this block
    
    // ========== SIMT Stack ==========
    // Stack signals
    reg simt_push, simt_pop;
    reg [PROGRAM_MEM_ADDR_BITS-1:0] simt_push_pc;
    reg [THREADS_PER_BLOCK-1:0]     simt_push_mask;
    reg [PROGRAM_MEM_ADDR_BITS-1:0] simt_push_reconvpc;
    
    wire [PROGRAM_MEM_ADDR_BITS-1:0] simt_tos_pc;
    wire [THREADS_PER_BLOCK-1:0]     simt_tos_mask;
    wire [PROGRAM_MEM_ADDR_BITS-1:0] simt_tos_reconvpc;
    wire simt_empty, simt_full;
    
    simt_stack #(
        .THREADS_PER_BLOCK(THREADS_PER_BLOCK),
        .STACK_DEPTH(2),
        .PC_BITS(PROGRAM_MEM_ADDR_BITS)
    ) stack (
        .clk(clk),
        .reset(reset),
        .push(simt_push),
        .pop(simt_pop),
        .push_pc(simt_push_pc),
        .push_mask(simt_push_mask),
        .push_reconvpc(simt_push_reconvpc),
        .tos_pc(simt_tos_pc),
        .tos_mask(simt_tos_mask),
        .tos_reconvpc(simt_tos_reconvpc),
        .empty(simt_empty),
        .full(simt_full)
    );
    
    // ========== Divergence Detection ==========
    // Analyze per-thread next_pc to detect divergence
    // For BRnzp: threads may jump to different PCs
    
    // taken_mask: threads that take the branch (next_pc != current_pc + 1)
    // not_taken_mask: threads that don't take the branch (next_pc == current_pc + 1)
    reg [THREADS_PER_BLOCK-1:0] taken_mask;
    reg [THREADS_PER_BLOCK-1:0] not_taken_mask;
    reg [PROGRAM_MEM_ADDR_BITS-1:0] branch_target;
    reg [PROGRAM_MEM_ADDR_BITS-1:0] fallthrough_pc;
    reg is_divergent;
    
    integer i;
    
    always @(*) begin
        taken_mask = {THREADS_PER_BLOCK{1'b0}};
        not_taken_mask = {THREADS_PER_BLOCK{1'b0}};
        branch_target = next_pc[0];
        fallthrough_pc = current_pc + 1;
        is_divergent = 1'b0;
        
        // Only check active threads
        for (i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin
            if (active_mask[i]) begin
                if (next_pc[i] != fallthrough_pc) begin
                    taken_mask[i] = 1'b1;
                    branch_target = next_pc[i];  // Use last taken thread's target
                end else begin
                    not_taken_mask[i] = 1'b1;
                end
            end
        end
        
        // Divergent if both taken and not_taken have active threads
        is_divergent = (taken_mask != 0) && (not_taken_mask != 0);
    end
    
    // ========== Main State Machine ==========
    always @(posedge clk) begin 
        // Default: no push/pop
        simt_push <= 1'b0;
        simt_pop <= 1'b0;
        
        if (reset) begin
            current_pc <= 0;
            core_state <= IDLE;
            done <= 0;
            active_mask <= {THREADS_PER_BLOCK{1'b1}}; // All threads active initially
        end else begin 
            case (core_state)
                IDLE: begin
                    if (start) begin 
                        core_state <= FETCH;
                        active_mask <= {THREADS_PER_BLOCK{1'b1}}; // Reset mask on new block
                    end
                end
                
                FETCH: begin 
                    if (fetcher_state == 3'b010) begin 
                        core_state <= DECODE;
                    end
                end
                
                DECODE: begin
                    core_state <= REQUEST;
                end
                
                REQUEST: begin 
                    core_state <= WAIT;
                end
                
                WAIT: begin
                    reg any_lsu_waiting;
                    any_lsu_waiting = 1'b0;
                    for (i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin
                        if (active_mask[i] && (lsu_state[i] == 2'b01 || lsu_state[i] == 2'b10)) begin
                            any_lsu_waiting = 1'b1;
                        end
                    end
                    if (!any_lsu_waiting) begin
                        core_state <= EXECUTE;
                    end
                end
                
                EXECUTE: begin
                    core_state <= UPDATE;
                end
                
                UPDATE: begin 
                    if (decoded_ret) begin 
                        // Check if all threads have hit RET (i.e., stack is empty)
                        if (simt_empty) begin
                            done <= 1;
                            core_state <= DONE;
                        end else begin
                            // Some threads still need to execute other paths
                            // Pop the stack and continue
                            simt_pop <= 1'b1;
                            current_pc <= simt_tos_pc;
                            active_mask <= simt_tos_mask;
                            core_state <= FETCH;
                        end
                    end else begin
                        // ========== Branch Divergence Handling ==========
                        if (decoded_pc_mux == 2'd1 && is_divergent && !simt_full) begin
                            // Divergent BRnzp: push not-taken path, continue with taken path
                            // reconvPC = the larger of the two targets (simple heuristic)
                            simt_push <= 1'b1;
                            simt_push_pc <= fallthrough_pc;
                            simt_push_mask <= not_taken_mask;
                            // reconvPC: assume then-branch ends at branch_target + some_offset
                            // For simplicity, use a fixed reconvPC at max(branch_target, fallthrough_pc) + 10
                            // In real impl, compiler provides this; here we use a simple rule
                            simt_push_reconvpc <= (branch_target > fallthrough_pc) ? 
                                                  branch_target + 8'd5 : fallthrough_pc + 8'd5;
                            
                            // Continue with taken path
                            current_pc <= branch_target;
                            active_mask <= taken_mask;
                            core_state <= FETCH;
                        end
                        // ========== Explicit Reconvergence (RECONV instruction) ==========
                        else if (decoded_reconv) begin
                            if (!simt_empty) begin
                                // RECONV: switch to the other branch path from stack
                                simt_pop <= 1'b1;
                                current_pc <= simt_tos_pc;  // Jump to stacked branch
                                active_mask <= simt_tos_mask;  // Activate those threads
                                core_state <= FETCH;
                            end else begin
                                // Stack empty: all branches have executed, continue normally
                                current_pc <= current_pc + 1;
                                active_mask <= {THREADS_PER_BLOCK{1'b1}};  // All threads active
                                core_state <= FETCH;
                            end
                        end
                        // ========== Normal Execution ==========
                        else begin
                            // No divergence or already converged
                            // Use next_pc from any active thread (they should all agree)
                            for (i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin
                                if (active_mask[i]) begin
                                    current_pc <= next_pc[i];
                                end
                            end
                            core_state <= FETCH;
                        end
                    end
                end
                
                DONE: begin 
                    // no-op
                end
            endcase
        end
    end
endmodule

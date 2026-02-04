`default_nettype none
`timescale 1ns/1ns

// PROGRAM COUNTER
// > Calculates the next PC for each thread to update to (but currently we assume all threads
//   update to the same PC and don't support branch divergence)
// > Currently, each thread in each core has it's own calculation for next PC
// > The NZP register value is set by the CMP instruction (based on >/=/< comparison) to 
//   initiate the BRnzp instruction for branching
module pc #(
    parameter DATA_MEM_DATA_BITS = 8,
    parameter PROGRAM_MEM_ADDR_BITS = 8
) (
    input wire clk,
    input wire reset,
    input wire enable, // If current block has less threads then block size, some PCs will be inactive

    // State
    input reg [2:0] core_state,

    // Control Signals
    input reg [2:0] decoded_nzp,
    input reg [DATA_MEM_DATA_BITS-1:0] decoded_immediate,
    input reg decoded_nzp_write_enable,
    input reg [1:0] decoded_pc_mux,  // 0=PC+1, 1=BRnzp, 2=JMP

    // ALU Output - used for alu_out[2:0] to compare with NZP register
    input reg [DATA_MEM_DATA_BITS-1:0] alu_out,
    
    // Register value for JMP instruction (Rs value)
    input reg [DATA_MEM_DATA_BITS-1:0] rs_value,

    // Current & Next PCs
    input reg [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] next_pc
);
    reg [2:0] nzp;

    always @(posedge clk) begin
        if (reset) begin
            nzp <= 3'b0;
            next_pc <= 0;
        end else if (enable) begin
            // Update PC when core_state = EXECUTE
            if (core_state == 3'b101) begin 
                case (decoded_pc_mux)
                    2'd0: begin
                        // Default: PC + 1
                        next_pc <= current_pc + 1;
                    end
                    2'd1: begin
                        // BRnzp: conditional branch
                        if ((nzp & decoded_nzp) != 3'b0) begin 
                            next_pc <= decoded_immediate;
                        end else begin 
                            next_pc <= current_pc + 1;
                        end
                    end
                    2'd2: begin
                        // JMP: unconditional jump to register value
                        next_pc <= rs_value;
                    end
                    default: begin
                        next_pc <= current_pc + 1;
                    end
                endcase
            end   

            // Store NZP when core_state = UPDATE   
            if (core_state == 3'b110) begin 
                // Write to NZP register on CMP instruction
                if (decoded_nzp_write_enable) begin
                    nzp[2] <= alu_out[2];
                    nzp[1] <= alu_out[1];
                    nzp[0] <= alu_out[0];
                end
            end      
        end
    end

endmodule

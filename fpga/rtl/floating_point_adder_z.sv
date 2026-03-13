/* Floating Point Adder Z
 * Mimics a floating point adder to buffer other streams
 * of data.
 */


module floating_point_adder_z #(
    parameter EXP_WIDTH  = 0,
    parameter FRAC_WIDTH = 0,
    parameter SAVE_FF = 1,

    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter FP_WIDTH_REG = 1 + EXP_WIDTH + FRAC_WIDTH
) (
    input clk_i,
    input rst_i,

    input  [FP_WIDTH_REG - 1 : 0] fp_a_i,
    input                         valid_i,

    output [FP_WIDTH_REG - 1 : 0] fp_o,
    output                        valid_o
);
    ////////////////////////////////////////////////////////////////
    // Input Registers
    logic [FP_WIDTH_REG - 1 : 0] fp_a_reg [7];
    logic                        valid_reg[7];

    always_ff @(posedge clk_i) begin
        if(SAVE_FF == 0) begin
            // 7 stages 
            fp_a_reg[0]  <= fp_a_i;
            for(int i = 1; i < 7; i++) begin
                fp_a_reg[i] <= fp_a_reg[i-1];
            end
            if(rst_i) begin
                for(int i = 0; i < 7; i++) begin
                    valid_reg[i] <= 0;
                end
            end else begin  
                valid_reg[0] <= valid_i;
                for(int i = 1; i < 7; i++) begin
                    valid_reg[i] <= valid_reg[i-1];
                end
            end
        end else begin
            // 1 stage 
            fp_a_reg[0]  <= fp_a_i;
            fp_a_reg[1]  <= fp_a_reg[0];
            fp_a_reg[2]  <= fp_a_reg[1];
            if(rst_i) begin
                valid_reg[0] <= 0;
                valid_reg[1] <= 0;
                valid_reg[2] <= 0;
            end else begin  
                valid_reg[0] <= valid_i;
                valid_reg[1] <= valid_reg[0];
                valid_reg[2] <= valid_reg[1];
            end
        end
    end
    
    ////////////////////////////////////////////////////////////////
    // Output
    assign fp_o    = (SAVE_FF == 0) ? fp_a_reg[6] : fp_a_reg[0];
    assign valid_o = (SAVE_FF == 0) ? valid_reg[6] : valid_reg[0];
endmodule


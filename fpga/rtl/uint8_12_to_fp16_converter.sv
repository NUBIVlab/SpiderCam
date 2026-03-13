/*
 * uint8 to fp16 converter
 *
 */

 module uint8_12_to_fp16_converter #(
    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter EXP_WIDTH = 5,
    parameter FRAC_WIDTH = 10,
    parameter FP_WIDTH_REG = 1 + FRAC_WIDTH + EXP_WIDTH,
    parameter EXP_MAX = 2**(EXP_WIDTH) - 1,
    parameter BIAS = 2**(EXP_WIDTH - 1) - 1 - 12
) (
    input clk_i,
    input rst_i,

    input  [20 - 1 : 0]           uint8_12_i,
    input                         valid_i,

    output [FP_WIDTH_REG - 1 : 0] fp16_o,
    output                        valid_o
);
    logic [20 - 1 : 0] uint8_12;
    logic             valid;

    always@(posedge clk_i) begin
        uint8_12 <= uint8_12_i;
        if(rst_i) begin
            valid <= 0;
        end else begin
            valid <= valid_i;
        end 
    end

    logic [EXP_WIDTH - 1 : 0] fp_exp;
    logic [FRAC_WIDTH - 1 : 0] fp_frac;
    logic [19:0] uint8_12_sh;

    always_comb begin
        fp_exp = 0;
        fp_frac = 0;
        uint8_12_sh = 0;
        
        for(int i = 0; i < 20; i++) begin
            if(uint8_12[i] == 1) begin
                fp_exp  = BIAS + i;
                uint8_12_sh = uint8_12 << (20 - i);
                fp_frac[FRAC_WIDTH - 1: 0] = uint8_12_sh[19:(20-10)]; 
                // rouding neglected to simplify hardware.
            end 
        end
        
    end

    assign fp16_o = {1'b0, fp_exp, fp_frac};
    assign valid_o = valid;
    
endmodule
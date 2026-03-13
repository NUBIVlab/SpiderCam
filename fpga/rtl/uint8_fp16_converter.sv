/*
 * uint8 to fp16 converter
 *
 */

 module uint8_fp16_converter #(
    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter EXP_WIDTH = 5,
    parameter FRAC_WIDTH = 10,
    parameter FP_WIDTH_REG = 1 + FRAC_WIDTH + EXP_WIDTH,
    parameter EXP_MAX = 2**(EXP_WIDTH) - 1,
    parameter BIAS = 2**(EXP_WIDTH - 1) - 1
) (
    input clk_i,
    input rst_i,

    input  [8 - 1 : 0]            uint8_i,
    input                         valid_i,

    output [FP_WIDTH_REG - 1 : 0] fp16_o,
    output                        valid_o
);
    logic [8 - 1 : 0] uint8;
    logic             valid;

    always@(posedge clk_i) begin
        uint8 <= uint8_i;
        if(rst_i) begin
            valid <= 0;
        end else begin
            valid <= valid_i;
        end 
    end

    logic [EXP_WIDTH - 1 : 0] fp_exp;
    logic [FRAC_WIDTH - 1 : 0] fp_frac;
    logic [7:0] uint8_sh;

    always_comb begin
        fp_exp = 0;
        fp_frac = 0;
        uint8_sh = 0;
        
        for(int i = 0; i < 8; i++) begin
            if(uint8[i] == 1) begin
                fp_exp  = BIAS + i;
                uint8_sh = uint8 << (8 - i);
                fp_frac[FRAC_WIDTH - 1: FRAC_WIDTH - 8] = uint8_sh; 
            end 
        end
        
    end

    assign fp16_o = {1'b0, fp_exp, fp_frac};
    assign valid_o = valid;
    
endmodule
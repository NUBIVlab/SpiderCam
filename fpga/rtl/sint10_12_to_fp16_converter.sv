/*
 * uint8 to fp16 converter
 *
 */

 module sint10_12_to_fp16_converter #(
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

    input  [21:0]                 sint10_12_i,
    input                         valid_i,

    output [FP_WIDTH_REG - 1 : 0] fp16_o,
    output                        valid_o
);
    logic [21:0] sint10_12;
    logic        valid;

    always@(posedge clk_i) begin
        sint10_12 <= sint10_12_i;
        if(rst_i) begin
            valid <= 0;
        end else begin
            valid <= valid_i;
        end 
    end

    logic                      fp_sign;
    logic [EXP_WIDTH - 1 : 0]  fp_exp;
    logic [FRAC_WIDTH - 1 : 0] fp_frac;
    logic [21:0] uint10_12;
    logic [21:0] uint10_12_sh;

    always_comb begin
        fp_sign = 0;
        fp_exp = 0;
        fp_frac = 0;
        uint10_12_sh = 0;

        uint10_12 = sint10_12;
        if(sint10_12[21]) begin
            fp_sign = 1;
            uint10_12 = ~uint10_12 + 1;
        end
        
        for(int i = 0; i < 22; i++) begin
            if(uint10_12[i] == 1) begin
                fp_exp  = BIAS + i;
                uint10_12_sh = uint10_12 << (22 - i);
                fp_frac[FRAC_WIDTH - 1: 0] = uint10_12_sh[21:(22-FRAC_WIDTH)]; 
                // rouding neglected to simplify hardware.
            end 
        end
        
    end

    assign fp16_o = {fp_sign, fp_exp, fp_frac};
    assign valid_o = valid;
    
endmodule
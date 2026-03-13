/*
 * fp16 to unsigned 8-bit converter with rounding.
 * (doesn't handle max overflow case when rounding)
 *
 * LEAD_EXPONENT_UNBIASED describes at what exponent
 * the MSB of the uint8 is. e.g for a regular
 * uint8, we would set this to 7 (2**7 = 128). But
 * we could have say half the bits represent integral
 * part and the other half frac by setting it to
 * 3, to get this unsigned 8 bit number.
 * 
 * | 2**3 | 2**2 | 2**1 | 2**0 | 2**-1 | 2**-2 | 2**-3 | 2**-4 |
 *
 *
 * if the exponent is larger than we can handle, set max value.
 * if the exponent is smaller than we can handle, set 0.
 * if the value is negative, set 0.
 */

module fp16_u8_converter #(
    parameter LEAD_EXPONENT_UNBIASED,

    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter EXP_WIDTH = 5,
    parameter FRAC_WIDTH = 10,
    parameter FP_WIDTH_REG = 1 + FRAC_WIDTH + EXP_WIDTH,
    parameter EXP_MAX = 2**(EXP_WIDTH) - 1,
    parameter BIAS = 2**(EXP_WIDTH - 1) - 1,
    parameter LEAD_EXPONENT = LEAD_EXPONENT_UNBIASED + BIAS,
    parameter LSB_EXPONENT = LEAD_EXPONENT - EXP_WIDTH
) (
    input clk_i,
    input rst_i,

    input  [FP_WIDTH_REG - 1 : 0] fp16_i,
    input                         valid_i,

    output [8 - 1 : 0]            u8_o,
    output                        valid_o
);
    logic [FP_WIDTH_REG - 1 : 0] fp16;
    logic                        valid;

    always@(posedge clk_i) begin
        fp16 <= fp16_i;
        if(rst_i) begin
            valid <= 0;
        end else begin
            valid <= valid_i;
        end 
    end

    logic [8:0] nine_bit;
    logic [7:0] eight_bit;
    logic unsigned [4:0] exp;
    logic unsigned [4:0] exp_diff;

    always_comb begin
        exp = fp16[14:10];
        nine_bit = {1'b1,fp16[9:2]};
        exp_diff = LEAD_EXPONENT - exp;

        if(exp > LEAD_EXPONENT) begin
            nine_bit = {{8{1'b1}},1'b0};
        end else if(exp < LSB_EXPONENT) begin
            nine_bit = 0;
        end else begin
            nine_bit = nine_bit >> exp_diff;
        end

        if(fp16[15]) begin
            nine_bit = 0;
        end

        // round
        nine_bit = nine_bit + 1;
        eight_bit = nine_bit[8:1];
    end

    assign u8_o = eight_bit;
    assign valid_o = valid;
    
endmodule
`ifndef FLOATING_POINT_INF  
    `define FLOATING_POINT_INF
interface floating_point_inf #(
    parameter EXP_WIDTH = 0,
    parameter FRAC_WIDTH = 0,
    // local
    parameter FP_WIDTH_REG = 1 + EXP_WIDTH + FRAC_WIDTH
) (
    input clk_i,
    input rst_i
);
    logic [FP_WIDTH_REG - 1 : 0] fp_a_i;
    logic [FP_WIDTH_REG - 1 : 0] fp_b_i;
    logic                        valid_i;
    logic [FP_WIDTH_REG - 1 : 0] fp_o;
    logic                        valid_o;

endinterface
`endif 
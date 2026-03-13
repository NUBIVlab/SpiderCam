`ifndef CONVOLUTION_FLOATING_POINT_INF  
    `define CONVOLUTION_FLOATING_POINT_INF
interface convolution_floating_point_inf #(
    parameter EXP_WIDTH  = 0,
    parameter FRAC_WIDTH = 0,

    parameter WINDOW_WIDTH  = 0,
    parameter WINDOW_HEIGHT = 0,

    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter FP_WIDTH_REG = 1 + EXP_WIDTH + FRAC_WIDTH
) (
    input clk_i,
    input rst_i
);
    logic [FP_WIDTH_REG - 1 : 0] window_i [WINDOW_HEIGHT][WINDOW_WIDTH];
    logic [FP_WIDTH_REG - 1 : 0] kernel_i [WINDOW_HEIGHT][WINDOW_WIDTH];
    logic [15:0]                 col_i;
    logic [15:0]                 row_i;
    logic                        valid_i;

    logic [FP_WIDTH_REG - 1 : 0] data_o;
    logic [15:0]                 col_o;
    logic [15:0]                 row_o;
    logic                        valid_o;

endinterface
`endif 
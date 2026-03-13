`ifndef DFDD_INF  
    `define DFDD_INF
interface dfdd_inf #(
    parameter EXP_WIDTH  = 0,
    parameter FRAC_WIDTH = 0,
    parameter SCALES = 0,

    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter FP_WIDTH_REG = 1 + EXP_WIDTH + FRAC_WIDTH
) (
    input clk_i,
    input rst_i
);
    logic [7:0] i_rho_plus_uint8_i;
    logic [7:0] i_rho_minus_uint8_i;

    logic [FP_WIDTH_REG - 1 : 0] i_rho_plus_i;
    logic [FP_WIDTH_REG - 1 : 0] i_rho_minus_i;
    logic [15:0]                 col_i;
    logic [15:0]                 row_i;
    logic                        valid_i;

    logic [FP_WIDTH_REG - 1 : 0] w_i [SCALES][3];
    logic [FP_WIDTH_REG - 1 : 0] w_t_i;
    logic [FP_WIDTH_REG - 1 : 0] a_i [SCALES];

    logic [FP_WIDTH_REG - 1 : 0] z_o;
    logic [FP_WIDTH_REG - 1 : 0] c_o;
    logic [15:0]                 col_o;
    logic [15:0]                 row_o;
    logic                        valid_o;

endinterface
`endif 
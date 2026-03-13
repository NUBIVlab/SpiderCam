/*
AUTOGEN CONVOLUTION_FLOATING_WRAPPER
-- KERNEL -- 
[0.25, 0.75, 0.75, 0.25]

*/

module upsampler_sh_h_0_fp16 #(
    parameter EXP_WIDTH = 5,
    parameter FRAC_WIDTH = 10,

    parameter WINDOW_WIDTH = 4,
    parameter WINDOW_HEIGHT = 1,

    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter FP_WIDTH_REG = 1 + FRAC_WIDTH + EXP_WIDTH,

    parameter LINEAR_WIDTH        = WINDOW_WIDTH * WINDOW_HEIGHT, 
    parameter LINEAR_WIDTH_2CLOG2 = 2 ** $clog2(LINEAR_WIDTH),     
    
    parameter OPT_DATA_WIDTH                           = EXP_WIDTH * 2,                     
    parameter EXP_MAX                                  = 2**EXP_WIDTH - 1,                  
    parameter [OPT_DATA_WIDTH - 1 : 0] DOUBLE_EXP_MAX  = 2**(EXP_WIDTH + EXP_WIDTH) - 1, 

    parameter OPTIMAL_ADD_LEVELS = $clog2(LINEAR_WIDTH_2CLOG2) 
) (
    input clk_i,
    input rst_i,

    input  [FP_WIDTH_REG - 1 : 0] window_i [WINDOW_HEIGHT][WINDOW_WIDTH],
    input  [FP_WIDTH_REG - 1 : 0] kernel_i [WINDOW_HEIGHT][WINDOW_WIDTH],
    input  [15:0]                 col_i,
    input  [15:0]                 row_i,
    input                         valid_i,

    output [FP_WIDTH_REG - 1 : 0] data_o,
    output [15:0]                 col_o,
    output [15:0]                 row_o,
    output                        valid_o
);
    localparam [OPT_DATA_WIDTH - 1 : 0] OPTIMAL_MULT [LINEAR_WIDTH] =
'{
10'b0000111110,10'b1111111111,10'b1111111111,10'b0000111110};

    localparam [0:0] OPTIMAL_ADD  [OPTIMAL_ADD_LEVELS][LINEAR_WIDTH_2CLOG2] = 
'{
'{1,1,1,1},
'{1,1,        0,0}
};

    convolution_floating_point #(
        .EXP_WIDTH(EXP_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),

        .WINDOW_WIDTH(WINDOW_WIDTH),
        .WINDOW_HEIGHT(WINDOW_HEIGHT),

        .OPTIMAL_MULT(OPTIMAL_MULT),
        .OPTIMAL_ADD(OPTIMAL_ADD)
    ) inst (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .window_i(window_i),
        .kernel_i(kernel_i),
        .col_i(col_i),
        .row_i(row_i),
        .valid_i(valid_i),

        .data_o(data_o),
        .col_o(col_o),
        .row_o(row_o),
        .valid_o(valid_o)
    );

endmodule
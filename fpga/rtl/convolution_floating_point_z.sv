/* Convolution Floating Point Z
 * Mimics data flow of convolution floating point.
 *
 * Designed to work with a Window Fetcher.
 */

 module convolution_floating_point_z #(
    parameter EXP_WIDTH  = 0,
    parameter FRAC_WIDTH = 0,

    parameter WINDOW_WIDTH  = 0,
    parameter WINDOW_HEIGHT = 0,

    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter FP_WIDTH_REG = 1 + FRAC_WIDTH + EXP_WIDTH,
    parameter LINEAR_WIDTH        = WINDOW_WIDTH * WINDOW_HEIGHT,  
    parameter LINEAR_WIDTH_2CLOG2 = 2 ** $clog2(LINEAR_WIDTH),
    parameter OPTIMAL_ADD_LEVELS = $clog2(LINEAR_WIDTH_2CLOG2)    

 ) (
    input clk_i,
    input rst_i,

    input  [FP_WIDTH_REG - 1 : 0] data_i,
    input  [15:0]                 col_i,
    input  [15:0]                 row_i,
    input                         valid_i,

    output [FP_WIDTH_REG - 1 : 0] data_o,
    output [15:0]                 col_o,
    output [15:0]                 row_o,
    output                        valid_o
 );

    ////////////////////////////////////////////////////////////////
    // Input Registers

    logic [FP_WIDTH_REG - 1 : 0] data;
    logic [15:0]                 col;
    logic [15:0]                 row;
    logic                        valid;

    always_ff@(posedge clk_i) begin
        data <= data_i;
        col <= col_i;
        row <= row_i;
        if(rst_i) begin
            valid <= 0;
        end else begin
            valid <= valid_i;
        end
    end

    ////////////////////////////////////////////////////////////////
    // Optimal Parallel Multiplication Generation
    logic [FP_WIDTH_REG - 1 : 0] mult_w;
    logic                        mult_valid_w;
    logic [15:0]                 mult_col_w;
    logic                        mult_col_valid_w;
    logic [15:0]                 mult_row_w;
    logic                        mult_row_valid_w;

    generate 
        floating_point_multiplier_z #(
            .EXP_WIDTH(EXP_WIDTH),
            .FRAC_WIDTH(FRAC_WIDTH)
        ) mult_data_delay (
            .clk_i(clk_i),
            .rst_i(rst_i),

            .fp_a_i (data),
            .valid_i(valid),

            .fp_o   (mult_w),
            .valid_o(mult_valid_w)
        );

        // we use floating_point_multiplier_z to delay row and col
        floating_point_multiplier_z #(
            .EXP_WIDTH(0),
            .FRAC_WIDTH(15)
        ) mult_col_delay (
            .clk_i(clk_i),
            .rst_i(rst_i),

            .fp_a_i (col),
            .valid_i(valid),

            .fp_o   (mult_col_w),
            .valid_o(mult_col_valid_w)
        );

        floating_point_multiplier_z #(
            .EXP_WIDTH(0),
            .FRAC_WIDTH(15)
        ) mult_row_delay (
            .clk_i(clk_i),
            .rst_i(rst_i),

            .fp_a_i (row),
            .valid_i(valid),

            .fp_o   (mult_row_w),
            .valid_o(mult_row_valid_w)
        );

    endgenerate

    ////////////////////////////////////////////////////////////////
    // Optimal Pipelined Adder Tree Generate
    logic [FP_WIDTH_REG - 1 : 0] add_levels_w   [OPTIMAL_ADD_LEVELS];
    logic [15:0]                 col_levels_w   [OPTIMAL_ADD_LEVELS];
    logic [15:0]                 row_levels_w   [OPTIMAL_ADD_LEVELS];
    logic                        valid_levels_w [OPTIMAL_ADD_LEVELS];
    logic                        valid_col_levels_w [OPTIMAL_ADD_LEVELS];
    logic                        valid_row_levels_w [OPTIMAL_ADD_LEVELS];

    always_comb begin
        add_levels_w  [0] = mult_w;
        valid_levels_w[0] = mult_valid_w;
        col_levels_w[0] = mult_col_w;
        row_levels_w[0] = mult_row_w;
        valid_col_levels_w[0] = mult_col_valid_w;
        valid_row_levels_w[0] = mult_row_valid_w;
    end

    generate
        // Optimal Adder Tree
        localparam last = OPTIMAL_ADD_LEVELS - 1;

        for(genvar l = 1; l < OPTIMAL_ADD_LEVELS; l++) begin
            localparam l_up  = l - 1;
            floating_point_adder_z #(
                .EXP_WIDTH(EXP_WIDTH),
                .FRAC_WIDTH(FRAC_WIDTH)
            ) adder_delay (
                .clk_i(clk_i),
                .rst_i(rst_i),

                .fp_a_i (add_levels_w  [l_up]),
                .valid_i(valid_levels_w[l_up]),

                .fp_o   (add_levels_w  [l]),
                .valid_o(valid_levels_w[l])
            );
            
            // Col and Row Delays
            floating_point_adder_z #(
                .EXP_WIDTH(0),
                .FRAC_WIDTH(15)
            ) col_adder_delay (
                .clk_i(clk_i),
                .rst_i(rst_i),

                .fp_a_i (col_levels_w      [l_up]),
                .valid_i(valid_col_levels_w[l_up]),

                .fp_o   (col_levels_w      [l]),
                .valid_o(valid_col_levels_w[l])
            );

            floating_point_adder_z #(
                .EXP_WIDTH(0),
                .FRAC_WIDTH(15)
            ) row_adder_delay (
                .clk_i(clk_i),
                .rst_i(rst_i),

                .fp_a_i (row_levels_w      [l_up]),
                .valid_i(valid_row_levels_w[l_up]),

                .fp_o   (row_levels_w      [l]),
                .valid_o(valid_row_levels_w[l])
            );
        end

        ////////////////////////////////////////////////////////////////
        // Out - Wiring Last Level 
        floating_point_adder_z #(
            .EXP_WIDTH(EXP_WIDTH),
            .FRAC_WIDTH(FRAC_WIDTH)
        ) last_adder_delay (
            .clk_i(clk_i),
            .rst_i(rst_i),

            .fp_a_i (add_levels_w  [last]),
            .valid_i(valid_levels_w[last]),

            .fp_o   (data_o),
            .valid_o(valid_o)
        );
        
        // Col and Row Delays
        floating_point_adder_z #(
            .EXP_WIDTH(0),
            .FRAC_WIDTH(15)
        ) last_col_adder_delay (
            .clk_i(clk_i),
            .rst_i(rst_i),

            .fp_a_i (col_levels_w      [last]),
            .valid_i(valid_col_levels_w[last]),

            .fp_o   (col_o),
            .valid_o()
        );

        floating_point_adder_z #(
            .EXP_WIDTH(0),
            .FRAC_WIDTH(15)
        ) last_row_adder_delay (
            .clk_i(clk_i),
            .rst_i(rst_i),

            .fp_a_i (row_levels_w      [last]),
            .valid_i(valid_row_levels_w[last]),

            .fp_o   (row_o),
            .valid_o()
        );

    endgenerate
endmodule
/* Convolution Floating Point
 * Applies a convolution between a window and kernel. The data type is parameterized floating point.
 * Note that the complete DATA_WIDTH for floating point is:
 * 1 + EXP_WIDTH + FRAC_WIDTH, 
 * not just 
 * EXP_WIDTH + FRAC_WIDTH.
 * due to adding the sign bit.
 *
 * Features an OPTIMAL_MULT parameter, which describes for each element in the kernel whether an
 * optimization can be made if multiplying a by a power of 2 or by 0.

 * MSB      | LSB      | meaning 
 * ---------------------------------
 * 0x00..0  | 0x00..0  | multiply by 0
 * 0x00..1  | 0x??..?  | multiply by + 2**(??)
 * 0x00..2  | 0x??..?  | multiply by - 2**(??)
 * 0xff..f  | 0xff..f  | no optimization
 *
 * LSB is treated as signed and has the width of EXP_WIDTH.
 * For simplicity, the MSB also has the width EXP_WIDTH.
 *
 * Features an OPTIMAL_ADD parameter, which unfortunately, we have to
 * optimize at each level of the adder tree manually.
 * 0 - means there is nothing to add
 * 1 - means there is something to add
 *
 * There are some nuances on how to do this, so here is a concrete examples:
 * lets say the kernel is:
 * [[ 0, 0, 5],
 *  [-8, 1, 3],
 *  [ 0, 7, 1/16]]
 * and my EXP_WIDTH = 5.
 *
 * localparam MY_OPTIMAL_MULT = '{10'b00000_00000, 10'b00000_00000, 10'b11111_11111,
 *                                10'b00010_00011, 10'b00001_00000, 10'b11111_11111,
 *                                10'b00000_00000, 10'b11111_11111, 10'b00001_11011};
 *
 * Notice it is linear array. I wrote it textually as such so that it is easy to
 * see how the linear array maps onto the 2D kernel. 
 *
 * I'm going to write it flat so that it helps in the next step.
 * localparam MY_OPTIMAL_MULT = '{10'b00000_00000, 10'b00000_00000, 10'b11111_11111, 10'b00010_00011, 10'b00001_00000, 10'b11111_11111, 10'b00000_00000, 10'b11111_11111, 10'b00001_11011};
 *
 * In order to set the OPTIMAL_ADD parameter, we need to find the nearest 2 power of the linear indices:
 * - 2 ** $clog2(WINDOW_WIDTH * WINDOW_HEIGHT) = 2 ** $clog2(9) = 2 ** 4 = 16.
 * - the number of total levels is then $clog2(16) = 4
 *
 * For level 0, for indices that exist, the rule is if the MY_OPTIMAL_MULT[idx] is optimized to being multiplied by 0, then we should also put just a 0,
 * else it must be a 1. For the padded values (indices that don't exist) set it to 0. This last step is crucial, if those elements are set to 1, we will
 * be unnecessarily add +0 values together which just wastes resources big time. Now for the i+1 level, we look at the parents to see if itself should 
 * be a 1. Only if both their parents are 0 then should it be set to 0, othwerwise it must be 1. Sounds complicated but it's not, here is the pseudocode 
 * algorithm to calculate the 0th level and the further levels for clarity.

--------------------------------------------------------------------------------------------
LINEAR_WIDTH        = WINDOW_WIDTH * WINDOW_HEIGHT
LINEAR_WIDTH_2CLOG2 = 2 ** $clog2(LINEAR_WIDTH)
OPTIMAL_ADD_LEVELS  = $clog2(LINEAR_WIDTH_2CLOG2)

[0:0] OPTIMAL_ADD  [OPTIMAL_ADD_LEVELS][LINEAR_WIDTH_CLOG2] = {default:1} // everything starts as having 1

// 0th level
for(genvar l = 0; l < 0; l++) begin
    for(opt = 0; opt < LINEAR_WIDTH; opt++) begin
        if(OPTIMAL_MULT[opt] == 0) OPTIMAL_ADD[opt] = 0;
    end
    for(opt = LINEAR_WIDTH; opt < LINEAR_WIDTH_2CLOG2; opt++) begin
        OPTIMAL_ADD[opt] = 0;
    end
end

// rest of levels
for(l = 1; l < OPTIMAL_ADD_LEVELS; l++) begin
    for(opt = 0; opt < (2**(OPTIMAL_ADD_LEVELS - l)); opt++) begin
        l_up  = l - 1;
        idx_0 = opt * 2;
        idx_1 = opt * 2 + 1;
        if((optimal_add[l_up][idx_0] == 0) && (optimal_add[l_up][idx_1] == 0)) begin
            OPTIMAL_ADD[l][opt] = 0
        end
    end
end
----------------------------------------------------------------------------------------------
 * Going back to our example, this is what it would result as:
 *
 *                                               |---- 9 real values ------|-- 7 padded values -|
 * localparam [0:0] MY_OPTIMAL_ADD [4][16]  = '{'{0, 0, 1, 1, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0},
 *                                              '{0,    1,    1,    1,    1,    0,    0,    0, x,x,x,x,x,x,x,x},
 *                                              '{1,          0,          0,          0,       x,x,x,x,x,x,x,x,x,x,x,x},
 *                                              '{1,                      0,                   x,x,x,x,x,x,x,x,x,x,x,x,x,x}};
 *
 * The x values don't matter because they will never be used and so nominally set it to 0.
 * I recommend following this textual format to prevent bugs.
 *
 * As you can see, this optimal adder tree diagram can be statically determined using the algorithms above, but System
 * Verilog's lack of expressive power when setting constants limits us dearly, and so we are forced to manually calculate
 * these values (which no doubt can introduce bugs, so do this very carefully).
 *
 * New Feature! See 'optimal_convolution_floating_point_generator.py' to generate a wrapper file that figures
 * all of this out automatically just with knowing the kernel values.
 *
 * 'SAME_SIGN' if all values can be guaranteed to be the same sign, use SAME_SIGN = 1, this reduces the floating
 * point adder utilization by 50%.
 *
 * Designed to work with a Window Fetcher.
 */

 module convolution_floating_point #(
    parameter EXP_WIDTH  = 0,
    parameter FRAC_WIDTH = 0,

    parameter WINDOW_WIDTH  = 0,
    parameter WINDOW_HEIGHT = 0,

    parameter LINEAR_WIDTH        = WINDOW_WIDTH * WINDOW_HEIGHT,  // *local
    parameter LINEAR_WIDTH_2CLOG2 = 2 ** $clog2(LINEAR_WIDTH),     // *local
    
    parameter OPT_DATA_WIDTH                           = EXP_WIDTH * 2,                     // *local
    parameter EXP_MAX                                  = 2**EXP_WIDTH - 1,                  // *local
    parameter [OPT_DATA_WIDTH - 1 : 0] DOUBLE_EXP_MAX  = 2**(OPT_DATA_WIDTH) - 1,    // *local

    parameter [OPT_DATA_WIDTH - 1 : 0] OPTIMAL_MULT [LINEAR_WIDTH],

    parameter OPTIMAL_ADD_LEVELS = $clog2(LINEAR_WIDTH_2CLOG2),    // *local
    
    parameter [0:0] OPTIMAL_ADD  [OPTIMAL_ADD_LEVELS][LINEAR_WIDTH_2CLOG2],

    parameter SAME_SIGN = 0,

    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter FP_WIDTH_REG = 1 + FRAC_WIDTH + EXP_WIDTH

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

    ////////////////////////////////////////////////////////////////
    // Input Registers

    logic [FP_WIDTH_REG - 1 : 0] window [LINEAR_WIDTH];
    logic [FP_WIDTH_REG - 1 : 0] kernel [LINEAR_WIDTH];
    logic [15:0]                 col;
    logic [15:0]                 row;
    logic                        valid;

    always_ff@(posedge clk_i) begin
        for(int r = 0; r < WINDOW_HEIGHT; r++) begin
            for(int c = 0; c < WINDOW_WIDTH; c++) begin
                window[(r*WINDOW_WIDTH) + c] <= window_i[r][c];
                kernel[(r*WINDOW_WIDTH) + c] <= kernel_i[r][c];
            end
        end
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
    logic [FP_WIDTH_REG - 1 : 0] mult_w       [LINEAR_WIDTH];
    logic                        mult_valid_w [LINEAR_WIDTH];
    logic [15:0]                 mult_col_w;
    logic                        mult_col_valid_w;
    logic [15:0]                 mult_row_w;
    logic                        mult_row_valid_w;

    generate 
        for(genvar opt_mult = 0; opt_mult < LINEAR_WIDTH; opt_mult++) begin
            localparam [2 * EXP_WIDTH - 1 : 0] opt     = OPTIMAL_MULT[opt_mult];
            localparam [EXP_WIDTH - 1 : 0]     opt_msb = opt[(2*EXP_WIDTH - 1) : EXP_WIDTH];
            localparam [EXP_WIDTH - 1 : 0]     opt_lsb = opt[EXP_WIDTH - 1 : 0];

            // if by zero 
            if((opt_msb == 0) && (opt_lsb == 0)) begin
                // leave disconnected

            // if by power of 2
            end else if ((opt_msb == 1) || (opt_msb == 2)) begin
                floating_point_multiplier_exponent #(
                    .EXP_WIDTH (EXP_WIDTH),
                    .FRAC_WIDTH(FRAC_WIDTH),
                    .SIGN      (opt_msb == 1 ? 0 : 1),
                    .EXPONENT  (opt_lsb)
                ) by_exp_mult (
                    .clk_i(clk_i),
                    .rst_i(rst_i),
                    
                    .fp_a_i (window[opt_mult]),
                    .valid_i(valid),

                    .fp_o   (mult_w[opt_mult]),
                    .valid_o(mult_valid_w[opt_mult])
                );
            // no optimization
            end else if ((opt_msb == EXP_MAX) && (opt_lsb == EXP_MAX)) begin
                floating_point_multiplier #(
                    .EXP_WIDTH (EXP_WIDTH),
                    .FRAC_WIDTH(FRAC_WIDTH)
                ) mult (
                    .clk_i(clk_i),
                    .rst_i(rst_i),
                    
                    .fp_a_i (window[opt_mult]),
                    .fp_b_i (kernel[opt_mult]),
                    .valid_i(valid),

                    .fp_o   (mult_w[opt_mult]),
                    .valid_o(mult_valid_w[opt_mult])
                );

            // default no optimization
            end else begin
                floating_point_multiplier #(
                    .EXP_WIDTH (EXP_WIDTH),
                    .FRAC_WIDTH(FRAC_WIDTH)
                ) mult (
                    .clk_i(clk_i),
                    .rst_i(rst_i),
                    
                    .fp_a_i (window[opt_mult]),
                    .fp_b_i (kernel[opt_mult]),
                    .valid_i(valid),

                    .fp_o   (mult_w[opt_mult]),
                    .valid_o(mult_valid_w[opt_mult])
                );
            end
        end

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
    logic [FP_WIDTH_REG - 1 : 0] add_levels_w   [OPTIMAL_ADD_LEVELS][LINEAR_WIDTH_2CLOG2];
    logic [15:0]                 col_levels_w   [OPTIMAL_ADD_LEVELS];
    logic [15:0]                 row_levels_w   [OPTIMAL_ADD_LEVELS];
    logic                        valid_levels_w [OPTIMAL_ADD_LEVELS][LINEAR_WIDTH_2CLOG2];
    logic                        valid_col_levels_w [OPTIMAL_ADD_LEVELS];
    logic                        valid_row_levels_w [OPTIMAL_ADD_LEVELS];

    always_comb begin
        for(int opt = 0; opt < LINEAR_WIDTH; opt++) begin
            add_levels_w  [0][opt] = mult_w      [opt];
            valid_levels_w[0][opt] = mult_valid_w[opt];
        end
        for(int opt = LINEAR_WIDTH; opt < LINEAR_WIDTH_2CLOG2; opt++) begin
            add_levels_w  [0][opt] = 0;
            valid_levels_w[0][opt] = 0;
        end
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
            for(genvar opt = 0; opt < (2**(OPTIMAL_ADD_LEVELS - l)); opt++) begin
                localparam idx_0 = opt * 2;
                localparam idx_1 = (opt * 2) + 1;

                if((OPTIMAL_ADD[l_up][idx_0] == 0) && (OPTIMAL_ADD[l_up][idx_1] == 0)) begin
                    // leave disconnected
                end else if((OPTIMAL_ADD[l_up][idx_0] == 1) && (OPTIMAL_ADD[l_up][idx_1] == 0)) begin
                    // pass through left side
                    floating_point_adder_z #(
                        .EXP_WIDTH(EXP_WIDTH),
                        .FRAC_WIDTH(FRAC_WIDTH)
                    ) adder_left_pass (
                        .clk_i(clk_i),
                        .rst_i(rst_i),

                        .fp_a_i (add_levels_w  [l_up][idx_0]),
                        .valid_i(valid_levels_w[l_up][idx_0]),

                        .fp_o   (add_levels_w  [l][opt]),
                        .valid_o(valid_levels_w[l][opt])
                    );
                end else if((OPTIMAL_ADD[l_up][idx_0] == 0) && (OPTIMAL_ADD[l_up][idx_1] == 1)) begin
                    // pass through right side
                    floating_point_adder_z #(
                        .EXP_WIDTH(EXP_WIDTH),
                        .FRAC_WIDTH(FRAC_WIDTH)
                    ) adder_right_pass (
                        .clk_i(clk_i),
                        .rst_i(rst_i),

                        .fp_a_i (add_levels_w  [l_up][idx_1]),
                        .valid_i(valid_levels_w[l_up][idx_1]),

                        .fp_o   (add_levels_w  [l][opt]),
                        .valid_o(valid_levels_w[l][opt])
                    );
                end else begin
                    // genuine adder
                    floating_point_adder #(
                        .EXP_WIDTH(EXP_WIDTH),
                        .FRAC_WIDTH(FRAC_WIDTH),
                        .SAME_SIGN(SAME_SIGN)
                    ) adder (
                        .clk_i(clk_i),
                        .rst_i(rst_i),

                        .fp_a_i (add_levels_w    [l_up][idx_0]),
                        .fp_b_i (add_levels_w    [l_up][idx_1]),
                        .valid_i(valid_levels_w[l_up][idx_0]),

                        .fp_o   (add_levels_w  [l][opt]),
                        .valid_o(valid_levels_w[l][opt])
                    );
                end
            end

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
        if((OPTIMAL_ADD[last][0] == 0) && (OPTIMAL_ADD[last][1] == 0)) begin
            // leave disconnected
        end else if((OPTIMAL_ADD[last][0] == 1) && (OPTIMAL_ADD[last][1] == 0)) begin
            // pass through left side
            floating_point_adder_z #(
                .EXP_WIDTH(EXP_WIDTH),
                .FRAC_WIDTH(FRAC_WIDTH)
            ) last_adder_left_pass (
                .clk_i(clk_i),
                .rst_i(rst_i),

                .fp_a_i (add_levels_w    [last][0]),
                .valid_i(valid_levels_w[last][0]),

                .fp_o   (data_o),
                .valid_o(valid_o)
            );
        end else if((OPTIMAL_ADD[last][0] == 0) && (OPTIMAL_ADD[last][1] == 1)) begin
            // pass through right side
            floating_point_adder_z #(
                .EXP_WIDTH(EXP_WIDTH),
                .FRAC_WIDTH(FRAC_WIDTH)
            ) last_adder_right_pass (
                .clk_i(clk_i),
                .rst_i(rst_i),

                .fp_a_i (add_levels_w    [last][1]),
                .valid_i(valid_levels_w[last][1]),

                .fp_o   (data_o),
                .valid_o(valid_o)
            );
        end else begin
            // genuine adder
            floating_point_adder #(
                .EXP_WIDTH(EXP_WIDTH),
                .FRAC_WIDTH(FRAC_WIDTH),
                .SAME_SIGN(SAME_SIGN)
            ) last_adder (
                .clk_i(clk_i),
                .rst_i(rst_i),

                .fp_a_i (add_levels_w    [last][0]),
                .fp_b_i (add_levels_w    [last][1]),
                .valid_i(valid_levels_w[last][0]),

                .fp_o   (data_o),
                .valid_o(valid_o)
            );
        end

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
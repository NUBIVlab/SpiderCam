/* Floating Point Divider Z
 * to enable streaming data alongside.
 * *** READ ***
 * this really needs to be rewritten, currently
 * the delay depends on 'FRAC_EX_WIDTH' which depends
 * purely on 'FRAC_WIDTH'. This is completely inconsistent
 * with how i used other floating_*_z modules as delays
 * (sorry in advance).
 *
 */

module floating_point_divider_z #(
    parameter EXP_WIDTH = 0,
    parameter FRAC_WIDTH = 0,

    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter FP_WIDTH_REG = 1 + FRAC_WIDTH + EXP_WIDTH,
    parameter FRAC_EX_WIDTH = 1 + 1 + FRAC_WIDTH + 1

) (
    input clk_i,
    input rst_i,

    input  [FP_WIDTH_REG - 1 : 0] fp_a_i,
    input                         valid_i,

    output [FP_WIDTH_REG - 1 : 0] fp_o,
    output                        valid_o
);
    ////////////////////////////////////////////////////////////////
    // Input Registers
    logic [FP_WIDTH_REG - 1 : 0] fp_a_reg;
    logic                        valid_reg;

    always_ff @(posedge clk_i) begin
        fp_a_reg  <= fp_a_i;
        if(rst_i) begin
            valid_reg <= 0;
        end else begin  
            valid_reg <= valid_i;
        end
    end

    ////////////////////////////////////////////////////////////////
    // Pipelining values
    logic [FP_WIDTH_REG - 1 : 0] fp_reg_pipe    [FRAC_EX_WIDTH];
    logic                        valid_reg_pipe [FRAC_EX_WIDTH];

    always_ff@(posedge clk_i) begin
        fp_reg_pipe  [0] <= fp_a_reg;
        for(int p = 1; p < FRAC_EX_WIDTH; p++) begin
            fp_reg_pipe[p] <= fp_reg_pipe[p-1];
        end

        if(rst_i) begin
            for(int p = 0; p < FRAC_EX_WIDTH; p++) begin
                valid_reg_pipe[p] <= 0;
            end
        end else begin
            valid_reg_pipe[0] <= valid_reg;
            for(int p = 1; p < FRAC_EX_WIDTH; p++) begin
                valid_reg_pipe[p] <= valid_reg_pipe[p-1];
            end
        end
    end

    ////////////////////////////////////////////////////////////////
    // Exit
    
    assign fp_o    = fp_reg_pipe[FRAC_EX_WIDTH - 1];
    assign valid_o = valid_reg_pipe[FRAC_EX_WIDTH - 1];
endmodule
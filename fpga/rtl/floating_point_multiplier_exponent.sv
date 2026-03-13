/* Floating Point Multiplier Exponent
 * Optimizes for multiplying by powers of 2 or 0
 * (subnormal approximation rules still apply)
 */

 module floating_point_multiplier_exponent #(
    parameter EXP_WIDTH  = 0,
    parameter FRAC_WIDTH = 0,
    parameter SIGN       = 0,
    parameter EXPONENT   = 0,
    parameter BY_ZERO    = 0,
    parameter SAVE_FF    = 1,
    
    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter FP_WIDTH_REG = 1 + FRAC_WIDTH + EXP_WIDTH,
    parameter SIGN_IDX     = FRAC_WIDTH + EXP_WIDTH,
    parameter EXP_IDX_LSB  = FRAC_WIDTH,
    parameter EXP_IDX_MSB  = EXP_WIDTH + EXP_IDX_LSB - 1,
    parameter FRAC_IDX_LSB = 0,
    parameter FRAC_IDX_MSB = FRAC_WIDTH + FRAC_IDX_LSB - 1,
    parameter EXP_MAX = 2**EXP_WIDTH - 1
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
    logic [FP_WIDTH_REG - 1 : 0] fp_a_reg [2];
    logic                        valid_reg[2];

    logic                             fp_a_sign;
    logic        [EXP_WIDTH - 1 : 0]  fp_a_exp;
    logic signed [EXP_WIDTH  : 0]     fp_exp_result;
    logic        [FRAC_WIDTH - 1 : 0] fp_a_frac;

    logic signed [EXP_WIDTH : 0] EXPONENT_SEXT;
    assign EXPONENT_SEXT = {EXPONENT[EXP_WIDTH - 1], EXPONENT[EXP_WIDTH - 1 : 0]};
    
    logic [FP_WIDTH_REG - 1 : 0] fp_a_result;

    always_comb begin
        fp_a_sign = fp_a_reg[0][SIGN_IDX];
        fp_a_exp  = fp_a_reg[0][EXP_IDX_MSB : EXP_IDX_LSB];
        fp_a_frac = fp_a_reg[0][FRAC_IDX_MSB : FRAC_IDX_LSB];

        fp_a_sign = fp_a_sign ^ SIGN[0]; 

        fp_exp_result = {1'b0, fp_a_exp};
        fp_exp_result = fp_exp_result + EXPONENT_SEXT;
        
        // safe guard against wrap around issue
        if(fp_exp_result <= 0) begin
            fp_a_exp = 0;
        end else if(fp_exp_result >= EXP_MAX) begin
            fp_a_exp = EXP_MAX;
        end else begin
            fp_a_exp = fp_exp_result[EXP_WIDTH - 1 : 0];
        end


        if(BY_ZERO) begin
            fp_a_exp = 0;
            fp_a_frac = 0;
        end 

        fp_a_result = {fp_a_sign, fp_a_exp, fp_a_frac};
    end

    always_ff @(posedge clk_i) begin
        if(SAVE_FF == 0) begin
            // 2 stages 
            fp_a_reg[0]  <= fp_a_i;
            fp_a_reg[1]  <= fp_a_result;
            if(rst_i) begin
                valid_reg[0] <= 0;
                valid_reg[1] <= 0;
            end else begin  
                valid_reg[0] <= valid_i;
                valid_reg[1] <= valid_reg[0];
            end
        end else begin
            // 1 stages 
            fp_a_reg[0]  <= fp_a_i;
            if(rst_i) begin
                valid_reg[0] <= 0;
            end else begin  
                valid_reg[0] <= valid_i;
            end
        end
    end

    ////////////////////////////////////////////////////////////////
    // Output
    assign fp_o    = (SAVE_FF == 0) ? fp_a_reg[1] : fp_a_result ;
    assign valid_o = (SAVE_FF == 0) ? valid_reg[1] : valid_reg[0];

 endmodule
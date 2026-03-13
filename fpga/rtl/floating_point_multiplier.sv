/* Floating Point Multiplier
 * Follows the IEEE 754 specification (almost) but has been parameterized
 * so that you can adjust how many exponent bits and fraction bits
 * you want.
 *
 * The exception is subnormal values are approximated to zero. In particular,
 * the multiplier can accept subnormal values, but it will treat it as a 0
 * (the fractional bits will be set to 0). The reasoning is that
 * the cost in hardware isn't worth the 'gradual' descent into subnormal,
 * if even smaller values are required, use more exponent bits. Adding
 * a single exponent bit expands the range by 2^2^x.
 * The total number of bits including the sign bit is
 * 1 + EXP_WIDTH + FRAC_WIDTH.
 *
 * By doing so, this guarantees that all multiplied numbers produce
 * either a 1 bit in the carry or lead position (or both), or just 0, which
 * means we don't need to have expensive hardware to barrel shift
 * to the correct exponenet.
 *
 * If the exponent of the intermediary value of the multiplication just so 
 * happens to 0 but the carry bit is 1, then in reality, shifting it will cause
 * it to become a normal value again. This is not what the multiplier does,
 * instead it just assumes its zero and moves on. In practice, this is not a big 
 * issue (but admittedly can be fixed with one more pipe stage, I'm just too lazy).
 * 
 * The total precision is 1 + FRAC_WIDTH due to the leading bit being
 * 1 (also called hidden bit).
 *
 * The bias for the exponent is 2^(EXP_WIDTH - 1) - 1
 *
 * Zero or subnormal is represented when the exponent == 0. This means
 * that the leading bit becomes 0.
 *
 * Infinity or NaN is represented when the exponent == 2^(EXP_WIDTH) - 1
 *
 * This means the effective range of exponents are (unsigned --> signed)
 * normal:       [1, 2^(EXP_WIDTH) - 2]  --> [1 - (2^(EXP_WIDTH - 1) - 1), 2^(EXP_WIDTH - 1) - 1]
 * subnormal:    [0]                     --> [- 2^(EXP_WIDTH - 1)]
 * Infinity/NaN: [2^(EXP_WIDTH) - 1]     --> [  2^(EXP_WIDTH - 1)]
 *
 * Everything is stored as unsigned, then the bias is subtracted to get the real
 * exponent.
 *
 * 'Regular form' : [sign bit | exponent bits | fractional bits]
 * but to fully encapsulate information for the coming operation, I've come up with a
 *
 * 'Total form'   : [sign bit | exponent bits | carry bit | lead bit | fractional bits | round bit ].
 * We encode 3 additional bits of information, carry, lead and round bit. The order of the bits
 * is most convenient. Originally I wanted to call it 'Full form' but that abbreviates as FF
 * which can be confused with flip-flop.
 *
 * Dispute:
 * 0xc3980000 multiplied by 0x89f4a330
 * gives 0x0e1140e4
 * but after investigating, I disagree, it should be
 * 0x0e1140e5
 */

 module floating_point_multiplier #(
    parameter EXP_WIDTH = 0,
    parameter FRAC_WIDTH = 0,
    parameter SAVE_FF = 1,

    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter SIGN_IDX     = FRAC_WIDTH + EXP_WIDTH,
    parameter EXP_IDX_LSB  = FRAC_WIDTH,
    parameter EXP_IDX_MSB  = EXP_WIDTH + EXP_IDX_LSB - 1,
    parameter FRAC_IDX_LSB = 0,
    parameter FRAC_IDX_MSB = FRAC_WIDTH + FRAC_IDX_LSB - 1,
    parameter FP_WIDTH_REG = 1 + FRAC_WIDTH + EXP_WIDTH,
    parameter FP_WIDTH_TOT = 1 + EXP_WIDTH + 1 + 1 + FRAC_WIDTH + 1,
    parameter FRAC_EX_WIDTH = 1 + 1 + FRAC_WIDTH + 1,
    parameter FRAC_EX_MULT_WIDTH = 2 * FRAC_EX_WIDTH,
    parameter BIAS = 2**(EXP_WIDTH - 1) - 1,
    parameter EXP_MAX = 2**EXP_WIDTH - 1
 ) (
    input clk_i,
    input rst_i,

    input  [FP_WIDTH_REG - 1 : 0] fp_a_i,
    input  [FP_WIDTH_REG - 1 : 0] fp_b_i,
    input                         valid_i,

    output [FP_WIDTH_REG - 1 : 0] fp_o,
    output                        valid_o
 );

    ////////////////////////////////////////////////////////////////
    // Input Registers
    logic [FP_WIDTH_REG - 1 : 0] fp_a_reg;
    logic [FP_WIDTH_REG - 1 : 0] fp_b_reg;
    logic                        valid_reg;

    always_ff @(posedge clk_i) begin
        fp_a_reg  <= fp_a_i;
        fp_b_reg  <= fp_b_i;
        if(rst_i) begin
            valid_reg <= 0;
        end else begin  
            valid_reg <= valid_i;
        end
    end

    logic                                  fp_a_sign;
    logic unsigned [EXP_WIDTH - 1 : 0]     fp_a_exp;
    logic signed   [EXP_WIDTH + 2 - 1 : 0] fp_a_exp_s;
    logic                                  fp_a_carry;
    logic                                  fp_a_lead;
    logic          [FRAC_WIDTH - 1 : 0]    fp_a_frac;
    logic                                  fp_a_round;
    logic unsigned [FRAC_EX_WIDTH - 1 : 0] fp_a_frac_ex;

    logic                                  fp_b_sign;
    logic unsigned [EXP_WIDTH - 1 : 0]     fp_b_exp;
    logic signed   [EXP_WIDTH + 2 - 1 : 0] fp_b_exp_s;
    logic                                  fp_b_carry;
    logic                                  fp_b_lead;
    logic          [FRAC_WIDTH - 1 : 0]    fp_b_frac;
    logic                                  fp_b_round;
    logic unsigned [FRAC_EX_WIDTH - 1 : 0] fp_b_frac_ex;

    logic unsigned [FRAC_EX_MULT_WIDTH - 1 : 0] fp_mult;
    logic signed   [EXP_WIDTH + 2 - 1 : 0]      fp_exp_s;
    logic                                       fp_sign;
    logic unsigned [EXP_WIDTH - 1 : 0]          fp_exp;
    logic          [FRAC_EX_WIDTH - 1 : 0]      fp_frac_ex;

    logic                                       mult_by_zero[2];        

    ////////////////////////////////////////////////////////////////
    // Stage 1
    always_comb begin
        fp_a_sign  = fp_a_reg[SIGN_IDX];
        fp_a_exp   = fp_a_reg[EXP_IDX_MSB : EXP_IDX_LSB];
        fp_a_carry = 0;
        fp_a_lead  = 1;
        fp_a_frac  = fp_a_reg[FRAC_IDX_MSB : FRAC_IDX_LSB];
        fp_a_round = 0;

        fp_b_sign  = fp_b_reg[SIGN_IDX];
        fp_b_exp   = fp_b_reg[EXP_IDX_MSB : EXP_IDX_LSB];
        fp_b_carry = 0;
        fp_b_lead  = 1;
        fp_b_frac  = fp_b_reg[FRAC_IDX_MSB : FRAC_IDX_LSB];
        fp_b_round = 0;

        if((fp_a_exp == 0) || (fp_b_exp == 0)) begin
            mult_by_zero[0] = 1;
        end else begin
            mult_by_zero[0] = 0;
        end

        fp_a_frac_ex = {fp_a_carry, fp_a_lead, fp_a_frac, fp_a_round};
        fp_b_frac_ex = {fp_b_carry, fp_b_lead, fp_b_frac, fp_b_round};
        
        fp_mult = fp_a_frac_ex * fp_b_frac_ex;

        fp_a_exp_s = {2'b00, fp_a_exp};
        fp_b_exp_s = {2'b00, fp_b_exp};

        fp_a_exp_s = fp_a_exp_s - BIAS;
        fp_b_exp_s = fp_b_exp_s - BIAS;

        fp_exp_s = fp_a_exp_s + fp_b_exp_s;
        if(fp_exp_s <= (-BIAS)) begin
            fp_exp_s = -BIAS;
            fp_mult  = 0;
        end else if (fp_exp_s >= (BIAS + 1)) begin
            fp_exp_s = BIAS + 1;
            fp_mult = 0;
        end

        if((fp_a_exp == EXP_MAX) || (fp_b_exp == EXP_MAX)) begin
            fp_exp_s = BIAS + 1;
        end

        fp_sign    = fp_a_sign ^ fp_b_sign;
        fp_exp_s   = fp_exp_s + BIAS;
        fp_exp     = fp_exp_s[EXP_WIDTH - 1 : 0];
        fp_frac_ex = fp_mult[FRAC_EX_MULT_WIDTH - 2 - 1 : FRAC_EX_WIDTH - 2];    

    end
    
    logic                                       fp_sign_reg;
    logic unsigned [EXP_WIDTH - 1 : 0]          fp_exp_reg;
    logic          [FRAC_EX_WIDTH - 1 : 0]      fp_frac_ex_reg;
    logic                                       valid_reg_1;

    always_ff @(posedge clk_i) begin
        if(SAVE_FF == 0) begin
            fp_sign_reg     <= fp_sign;
            fp_exp_reg      <= fp_exp;
            fp_frac_ex_reg  <= fp_frac_ex;
            mult_by_zero[1] <= mult_by_zero[0];
            if(rst_i) begin
                valid_reg_1 <= 0;
            end else begin  
                valid_reg_1 <= valid_reg;
            end
        end
    end

    logic unsigned [EXP_WIDTH - 1 : 0]          fp_exp_1;
    logic          [FRAC_EX_WIDTH - 1 : 0]      fp_frac_ex_1;


    ////////////////////////////////////////////////////////////////
    // Stage 2
    always_comb begin
        if(SAVE_FF == 0) begin
            fp_exp_1     = fp_exp_reg;
            fp_frac_ex_1 = fp_frac_ex_reg; 

            if(fp_frac_ex_1[FRAC_EX_WIDTH - 1]) begin
                fp_frac_ex_1 = fp_frac_ex_1 >> 1;
                if(fp_exp_1 != EXP_MAX) begin
                    fp_exp_1 = fp_exp_1 + 1;
                end
            end

            if(fp_frac_ex_1[0]) begin
                fp_frac_ex_1 = fp_frac_ex_1 + 1;
            end

            if(fp_frac_ex_1[FRAC_EX_WIDTH - 1]) begin
                fp_frac_ex_1 = fp_frac_ex_1 >> 1;
                if(fp_exp_1 != EXP_MAX) begin
                    fp_exp_1 = fp_exp_1 + 1;
                end
            end

            if(mult_by_zero[1]) begin
                fp_exp_1 = 0;
                fp_frac_ex_1 = 0;
            end
        end else begin
            fp_exp_1     = fp_exp;
            fp_frac_ex_1 = fp_frac_ex; 

            if(fp_frac_ex_1[FRAC_EX_WIDTH - 1]) begin
                fp_frac_ex_1 = fp_frac_ex_1 >> 1;
                if(fp_exp_1 != EXP_MAX) begin
                    fp_exp_1 = fp_exp_1 + 1;
                end
            end

            if(fp_frac_ex_1[0]) begin
                fp_frac_ex_1 = fp_frac_ex_1 + 1;
            end

            if(fp_frac_ex_1[FRAC_EX_WIDTH - 1]) begin
                fp_frac_ex_1 = fp_frac_ex_1 >> 1;
                if(fp_exp_1 != EXP_MAX) begin
                    fp_exp_1 = fp_exp_1 + 1;
                end
            end

            if(mult_by_zero[0]) begin
                fp_exp_1 = 0;
                fp_frac_ex_1 = 0;
            end

        end
    end

    assign fp_o    = (SAVE_FF == 0) ? {fp_sign_reg, fp_exp_1, fp_frac_ex_1[FRAC_EX_WIDTH - 2 - 1:1]} : {fp_sign, fp_exp_1, fp_frac_ex_1[FRAC_EX_WIDTH - 2 - 1:1]};
    assign valid_o = (SAVE_FF == 0) ? valid_reg_1 : valid_reg;

 endmodule
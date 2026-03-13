/* Floating Point Adder
 * Follows the IEEE 754 specification (almost) but has been parameterized
 * so that you can adjust how many exponent bits and fraction bits
 * you want.
 *
 * The exception is subnormal values are approximated to zero. In particular,
 * the adder can accept subnormal values, but if the result produces a 
 * subnormal value, the fractional bit is set to zero. The reasoning is that
 * the cost in hardware isn't worth the 'gradual' descent into subnormal,
 * if even smaller values are required, use more exponent bits. Adding
 * a single exponent bit expands the range by 2^2^x.
 *
 * A second modification is then rather than adding two huge numbers
 * with a bunch of zeros padded (for the larger exponent one), i limit it just
 * to the round bit (see below 'total form'). In effective this makes no 
 * difference when adding two values of the same sign. But when different, the
 * result is often rounded up instead of down since negative values will
 * become smaller then they actually are. For example, 1.51 being 1.5 is fine for same
 * sign addition, but -1.51 being -1.5 means that a result will land on a .5 mark
 * causing it to be rounded up when reality it should land on smaller then .5 mark, 
 * which would correctly cause it to round down.
 *
 * The total number of bits including the sign bit is
 * 1 + EXP_WIDTH + FRAC_WIDTH.
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
 * If we can guarantee that both fp_a_i and fp_b_i are have the same sign always, in conjunction
 * with the subnormal approximation, we can heavily simplify the nr stage, saving lots of resources.
 * See the 'SAME_SIGN'
 */

module floating_point_adder #(
    parameter EXP_WIDTH  = 0,
    parameter FRAC_WIDTH = 0,
    parameter SAVE_FF = 1,
    parameter SAME_SIGN = 0,

    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter FP_WIDTH_REG = 1 + EXP_WIDTH + FRAC_WIDTH,
    parameter FP_WIDTH_TOT = 1 + EXP_WIDTH + 1 + 1 + FRAC_WIDTH + 1
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
    // 1 - sgm
    logic [FP_WIDTH_TOT - 1 : 0] sgm_ngm_fp_a_w;
    logic [FP_WIDTH_TOT - 1 : 0] sgm_ngm_fp_b_w;
    logic                        sgm_ngm_valid_w;
    logic [EXP_WIDTH - 1 : 0]    sgm_ngm_exp_diff_w;

    sgm #(
        .EXP_WIDTH(EXP_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH)
    ) sgm_inst (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .fp_a_i(fp_a_i),
        .fp_b_i(fp_b_i),
        .valid_i(valid_i),

        .fp_a_o(sgm_ngm_fp_a_w),
        .fp_b_o(sgm_ngm_fp_b_w),
        .exp_diff_o(sgm_ngm_exp_diff_w),
        .valid_o(sgm_ngm_valid_w)
    );

    ////////////////////////////////////////////////////////////////
    // 2 -  ngm
    logic [FP_WIDTH_TOT - 1 : 0] ngm_cvt_fp_a_w;
    logic [FP_WIDTH_TOT - 1 : 0] ngm_cvt_fp_b_w;
    logic                        ngm_cvt_valid_w;

    ngm #(
        .EXP_WIDTH(EXP_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),
        .SAVE_FF(SAVE_FF)
    ) ngm_inst (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .fp_a_i(sgm_ngm_fp_a_w),
        .fp_b_i(sgm_ngm_fp_b_w),
        .exp_diff_i(sgm_ngm_exp_diff_w),
        .valid_i(sgm_ngm_valid_w),

        .fp_a_o(ngm_cvt_fp_a_w),
        .fp_b_o(ngm_cvt_fp_b_w),
        .valid_o(ngm_cvt_valid_w)
    );

    ////////////////////////////////////////////////////////////////
    // 3 - cvt 
    logic [FP_WIDTH_TOT - 1 : 0] cvt_avt_fp_a_w;
    logic [FP_WIDTH_TOT - 1 : 0] cvt_avt_fp_b_w;
    logic                        cvt_avt_valid_w;

    cvt #(
        .EXP_WIDTH(EXP_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),
        .SAVE_FF(SAVE_FF)
    ) cvt_inst (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .fp_a_i(ngm_cvt_fp_a_w),
        .fp_b_i(ngm_cvt_fp_b_w),
        .valid_i(ngm_cvt_valid_w),

        .fp_a_o(cvt_avt_fp_a_w),
        .fp_b_o(cvt_avt_fp_b_w),
        .valid_o(cvt_avt_valid_w)
    );

    ////////////////////////////////////////////////////////////////
    // 4 - avt
    logic [FP_WIDTH_TOT - 1 : 0] avt_cvu_fp_w;
    logic                        avt_cvu_fp_a_sign_w;
    logic                        avt_cvu_fp_b_sign_w;
    logic                        avt_cvu_valid_w;

    avt #(
        .EXP_WIDTH(EXP_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),
        .SAVE_FF(SAVE_FF)
    ) avt_inst (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .fp_a_i(cvt_avt_fp_a_w),
        .fp_b_i(cvt_avt_fp_b_w),
        .valid_i(cvt_avt_valid_w),

        .fp_o(avt_cvu_fp_w),
        .fp_a_sign_o(avt_cvu_fp_a_sign_w),
        .fp_b_sign_o(avt_cvu_fp_b_sign_w),
        .valid_o(avt_cvu_valid_w)
    );

    ////////////////////////////////////////////////////////////////
    // 5 - cvu 
    logic [FP_WIDTH_TOT - 1 : 0] cvu_nr_fp_w;
    logic                        cvu_nr_valid_w;

    cvu #(
        .EXP_WIDTH(EXP_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),
        .SAVE_FF(SAVE_FF)
    ) cvu_inst (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .fp_i(avt_cvu_fp_w),
        .fp_a_sign_i(avt_cvu_fp_a_sign_w),
        .fp_b_sign_i(avt_cvu_fp_b_sign_w),
        .valid_i(avt_cvu_valid_w),

        .fp_o(cvu_nr_fp_w),
        .valid_o(cvu_nr_valid_w)
    );

    ////////////////////////////////////////////////////////////////
    // 6 - nr 
    logic [FP_WIDTH_TOT - 1 : 0] nr_rr_fp_w;
    logic                        nr_rr_valid_w;

    generate 
    if(SAME_SIGN == 0) begin
    nr #(
        .EXP_WIDTH(EXP_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),
        .SAVE_FF(SAVE_FF)
    ) nr_inst (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .fp_i(cvu_nr_fp_w),
        .valid_i(cvu_nr_valid_w),

        .fp_o(nr_rr_fp_w),
        .valid_o(nr_rr_valid_w)
    );
    end else begin
    nrss #(
        .EXP_WIDTH(EXP_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),
        .SAVE_FF(SAVE_FF)
    ) nr_inst (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .fp_i(cvu_nr_fp_w),
        .valid_i(cvu_nr_valid_w),

        .fp_o(nr_rr_fp_w),
        .valid_o(nr_rr_valid_w)
    );
    end
    endgenerate

    ////////////////////////////////////////////////////////////////
    // 7 - rr
    logic [FP_WIDTH_REG - 1 : 0] rr_o_fp_w;
    logic                        rr_o_valid_w;

    rr #(
        .EXP_WIDTH(EXP_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),
        .SAVE_FF(SAVE_FF)
    ) rr_inst (
        .clk_i(clk_i),
        .rst_i(rst_i),
        
        .fp_i(nr_rr_fp_w),
        .valid_i(nr_rr_valid_w),

        .fp_o(rr_o_fp_w),
        .valid_o(rr_o_valid_w)
    );

    ////////////////////////////////////////////////////////////////
    // Output
    assign fp_o    = rr_o_fp_w;
    assign valid_o = rr_o_valid_w;
endmodule

// Select Greater Magnitude (SGM) - stage 1
/* We have to identify the greater magnitude value by looking
 * at the exponent (sign doesn't matter) and reorder. We also
 * calculate the difference of the exponents and pass that down.
 * If the exponent == 0 then lead bit is 0 and the exponent is
 * set to 1. This is the value that should be used to calculate
 * the exponent difference. Output in total form.
 * [ == 0] [ == 0] - EXP_WIDTH
 * [ < ] - EXP_WIDTH
 * [ - ] - EXP_WIDTH
 */

module sgm #(
    parameter EXP_WIDTH = 0,
    parameter FRAC_WIDTH = 0,

    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter SIGN_IDX     = FRAC_WIDTH + EXP_WIDTH,
    parameter EXP_IDX_LSB  = FRAC_WIDTH,
    parameter EXP_IDX_MSB  = EXP_WIDTH + EXP_IDX_LSB - 1,
    parameter FRAC_IDX_LSB = 0,
    parameter FRAC_IDX_MSB = FRAC_WIDTH + FRAC_IDX_LSB - 1,
    parameter FP_WIDTH_REG = 1 + FRAC_WIDTH + EXP_WIDTH,
    parameter FP_WIDTH_TOT = 1 + EXP_WIDTH + 1 + 1 + FRAC_WIDTH + 1
) (
    input clk_i,
    input rst_i,

    input  [FP_WIDTH_REG - 1 : 0] fp_a_i,
    input  [FP_WIDTH_REG - 1 : 0] fp_b_i,
    input                         valid_i,

    output [FP_WIDTH_TOT - 1 : 0] fp_a_o,
    output [FP_WIDTH_TOT - 1 : 0] fp_b_o,
    output [EXP_WIDTH - 1 : 0]    exp_diff_o,
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

    ////////////////////////////////////////////////////////////////
    // Main
    logic                               fp_a_sign;
    logic unsigned [EXP_WIDTH - 1 : 0]  fp_a_exp;
    logic                               fp_a_carry;
    logic                               fp_a_lead;
    logic          [FRAC_WIDTH - 1 : 0] fp_a_frac;
    logic                               fp_a_round;

    logic                               fp_b_sign;
    logic unsigned [EXP_WIDTH - 1 : 0]  fp_b_exp;
    logic                               fp_b_carry;
    logic                               fp_b_lead;
    logic          [FRAC_WIDTH - 1 : 0] fp_b_frac;
    logic                               fp_b_round;

    logic                               tmp_sign;
    logic unsigned [EXP_WIDTH - 1 : 0]  tmp_exp;
    logic                               tmp_carry;
    logic                               tmp_lead;
    logic          [FRAC_WIDTH - 1 : 0] tmp_frac;
    logic                               tmp_round;

    logic unsigned [EXP_WIDTH - 1 : 0]  exp_diff;
    logic signed   [EXP_WIDTH : 0]      exp_const_diff;
    
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

        if(fp_a_exp == 0) begin 
            fp_a_lead = 0;
            fp_a_exp = 1;
        end
        if(fp_b_exp == 0) begin 
            fp_b_lead = 0;
            fp_b_exp = 1;
        end

        tmp_sign  = fp_a_sign;
        tmp_exp   = fp_a_exp;
        tmp_carry = fp_a_carry;
        tmp_lead  = fp_a_lead;
        tmp_frac  = fp_a_frac;
        tmp_round = fp_a_round;

        exp_const_diff = fp_a_exp - fp_b_exp;

        if(exp_const_diff[EXP_WIDTH]) begin
            fp_a_sign  = fp_b_sign;
            fp_a_exp   = fp_b_exp;
            fp_a_carry = fp_b_carry;
            fp_a_lead  = fp_b_lead;
            fp_a_frac  = fp_b_frac;
            fp_a_round = fp_b_round;

            fp_b_sign  = tmp_sign;
            fp_b_exp   = tmp_exp;
            fp_b_carry = tmp_carry;
            fp_b_lead  = tmp_lead;
            fp_b_frac  = tmp_frac;
            fp_b_round = tmp_round;
        end

        exp_diff = fp_a_exp - fp_b_exp;
    end

    ////////////////////////////////////////////////////////////////
    // Output
    assign fp_a_o = {fp_a_sign, 
                     fp_a_exp, 
                     fp_a_carry, 
                     fp_a_lead,
                     fp_a_frac,
                     fp_a_round};

    assign fp_b_o = {fp_b_sign,
                     fp_b_exp,
                     fp_b_carry,
                     fp_b_lead,
                     fp_b_frac,
                     fp_b_round};
    assign valid_o = valid_reg;
    assign exp_diff_o = exp_diff;
endmodule

// Normalize to Greater Magnitude (NGM) - stage 2
/* Using the exponent difference, we take fp_small
 * and right shift it so that it matches the same
 * magnitude. Since everything is in the total form,
 * maintaining lead, carry and round bit needs to be
 * kept in mind.
 * [ variable right shifter ] - FRAC_WIDTH
 */

module ngm #(
    parameter EXP_WIDTH = 0,
    parameter FRAC_WIDTH = 0,
    parameter SAVE_FF = 0,
    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter FRAC_EX_WIDTH = 1 + 1 + FRAC_WIDTH + 1,
    parameter FRAC_EX_IDX_LSB = 0,
    parameter FRAC_EX_IDX_MSB = FRAC_EX_WIDTH + FRAC_EX_IDX_LSB - 1,
    parameter EXP_IDX_LSB = FRAC_EX_WIDTH,
    parameter EXP_IDX_MSB = EXP_WIDTH + EXP_IDX_LSB - 1,
    parameter SIGN_IDX = EXP_WIDTH + FRAC_EX_WIDTH,
    parameter FP_WIDTH_TOT = 1 + EXP_WIDTH + FRAC_EX_WIDTH
) (
    input clk_i,
    input rst_i,

    input  [FP_WIDTH_TOT - 1 : 0] fp_a_i,
    input  [FP_WIDTH_TOT - 1 : 0] fp_b_i,
    input  [EXP_WIDTH - 1 : 0]    exp_diff_i,
    input                         valid_i,

    output [FP_WIDTH_TOT - 1 : 0] fp_a_o,
    output [FP_WIDTH_TOT - 1 : 0] fp_b_o,
    output                        valid_o
);
    

    ////////////////////////////////////////////////////////////////
    // Input Registers
    logic          [FP_WIDTH_TOT - 1 : 0] fp_a_reg;
    logic          [FP_WIDTH_TOT - 1 : 0] fp_b_reg;
    logic unsigned [EXP_WIDTH - 1 : 0]    exp_diff_reg;
    logic                                 valid_reg;

    always_ff @(posedge clk_i) begin
        if(SAVE_FF == 0) begin
            fp_a_reg     <= fp_a_i;
            fp_b_reg     <= fp_b_i;
            exp_diff_reg <= exp_diff_i[EXP_WIDTH - 1: 0];
            if(rst_i) begin
                valid_reg <= 0;
            end else begin
                valid_reg <= valid_i;
            end
        end
    end

    ////////////////////////////////////////////////////////////////
    // Main
    logic                         fp_a_sign;
    logic [EXP_WIDTH - 1 : 0]     fp_a_exp;
    logic [FRAC_EX_WIDTH - 1 : 0] fp_a_frac_ex;
    
    logic                         fp_b_sign;
    logic [EXP_WIDTH - 1 : 0]     fp_b_exp;
    logic [FRAC_EX_WIDTH - 1 : 0] fp_b_frac_ex;

    logic unsigned [EXP_WIDTH - 1 : 0] exp_diff_us_i;
    assign exp_diff_us_i = exp_diff_i [EXP_WIDTH - 1 : 0];

    always_comb begin
        if(SAVE_FF == 0) begin
            fp_a_sign    = fp_a_reg[SIGN_IDX];
            fp_a_exp     = fp_a_reg[EXP_IDX_MSB : EXP_IDX_LSB];
            fp_a_frac_ex = fp_a_reg[FRAC_EX_IDX_MSB : FRAC_EX_IDX_LSB];

            fp_b_sign    = fp_b_reg[SIGN_IDX];
            fp_b_exp     = fp_b_reg[EXP_IDX_MSB : EXP_IDX_LSB];
            fp_b_frac_ex = fp_b_reg[FRAC_EX_IDX_MSB : FRAC_EX_IDX_LSB];

            fp_b_exp = fp_a_exp;

            if(exp_diff_reg <= (1 + FRAC_WIDTH)) begin
                fp_b_frac_ex = fp_b_frac_ex >> exp_diff_reg;
            end else begin
                fp_b_frac_ex = 0;
            end
        end else begin
            fp_a_sign    = fp_a_i[SIGN_IDX];
            fp_a_exp     = fp_a_i[EXP_IDX_MSB : EXP_IDX_LSB];
            fp_a_frac_ex = fp_a_i[FRAC_EX_IDX_MSB : FRAC_EX_IDX_LSB];

            fp_b_sign    = fp_b_i[SIGN_IDX];
            fp_b_exp     = fp_b_i[EXP_IDX_MSB : EXP_IDX_LSB];
            fp_b_frac_ex = fp_b_i[FRAC_EX_IDX_MSB : FRAC_EX_IDX_LSB];

            if(exp_diff_us_i <= (1 + FRAC_WIDTH)) begin
                fp_b_frac_ex = fp_b_frac_ex >> exp_diff_us_i;
            end else begin
                fp_b_frac_ex = 0;
            end
        end

        
    end
    
    ////////////////////////////////////////////////////////////////
    // Output
    assign fp_a_o  = {fp_a_sign, fp_a_exp, fp_a_frac_ex};
    assign fp_b_o  = {fp_b_sign, fp_b_exp, fp_b_frac_ex};
    assign valid_o = (SAVE_FF == 0) ? valid_reg : valid_i;

    
endmodule


// Round off Normalized Value (RNV) - stage 3
/* We need to round the normalized value by using the round bit. Although,
 * we maintain a carry bit, if a shift occurred, rounding will not cause the
 * carry bit to become 1. This is important because if the carry bit became one
 * that would signal having to increment the exponent by 1 (which would throw
 * away all our efforts at normalize the magnitudes) Using total form, this just
 * means adding 1 to
 * 'frac_total' - carry bit, lead bit, FRAC_WIDTH, round_bit to fp_b.
 * [ + ] - FRAC_WIDTH
 */
module rnv #(
    parameter EXP_WIDTH = 0,
    parameter FRAC_WIDTH = 0,
    parameter SAVE_FF = 0,

    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter FRAC_EX_WIDTH = 1 + 1 + FRAC_WIDTH + 1,
    parameter FRAC_EX_IDX_LSB = 0,
    parameter FRAC_EX_IDX_MSB = FRAC_EX_WIDTH + FRAC_EX_IDX_LSB - 1,
    parameter EXP_IDX_LSB = FRAC_EX_WIDTH,
    parameter EXP_IDX_MSB = EXP_WIDTH + EXP_IDX_LSB - 1,
    parameter SIGN_IDX = EXP_WIDTH + FRAC_EX_WIDTH,
    parameter FP_WIDTH_TOT = 1 + EXP_WIDTH + FRAC_EX_WIDTH
) (
    input clk_i,
    input rst_i,

    input  [FP_WIDTH_TOT - 1 : 0] fp_a_i,
    input  [FP_WIDTH_TOT - 1 : 0] fp_b_i,
    input                         valid_i,

    output [FP_WIDTH_TOT - 1 : 0] fp_a_o,
    output [FP_WIDTH_TOT - 1 : 0] fp_b_o,
    output                        valid_o
);
    ////////////////////////////////////////////////////////////////
    // Input Registers
    logic [FP_WIDTH_TOT - 1 : 0] fp_a_reg;
    logic [FP_WIDTH_TOT - 1 : 0] fp_b_reg;
    logic                        valid_reg;

    always_ff @(posedge clk_i) begin
        if(SAVE_FF == 0) begin
            fp_a_reg     <= fp_a_i;
            fp_b_reg     <= fp_b_i;
            if(rst_i) begin
                valid_reg <= 0;
            end else begin
                valid_reg <= valid_i;
            end
        end
    end


    ////////////////////////////////////////////////////////////////
    // Main
    logic                         fp_b_sign;
    logic [EXP_WIDTH - 1 : 0]     fp_b_exp;
    logic [FRAC_EX_WIDTH - 1 : 0] fp_b_frac_ex;

    always_comb begin
        if(SAVE_FF == 0) begin
            fp_b_sign    = fp_b_reg[SIGN_IDX];
            fp_b_exp     = fp_b_reg[EXP_IDX_MSB : EXP_IDX_LSB];
            fp_b_frac_ex = fp_b_reg[FRAC_EX_IDX_MSB : FRAC_EX_IDX_LSB];

            if(fp_b_frac_ex[0]) fp_b_frac_ex = fp_b_frac_ex + 1;
        end else begin
            fp_b_sign    = fp_b_i[SIGN_IDX];
            fp_b_exp     = fp_b_i[EXP_IDX_MSB : EXP_IDX_LSB];
            fp_b_frac_ex = fp_b_i[FRAC_EX_IDX_MSB : FRAC_EX_IDX_LSB];

            if(fp_b_frac_ex[0]) fp_b_frac_ex = fp_b_frac_ex + 1;
        end
    end


    ////////////////////////////////////////////////////////////////
    // Output
    assign fp_a_o  = fp_a_reg;
    assign fp_b_o  = {fp_b_sign, fp_b_exp, fp_b_frac_ex};
    assign valid_o = (SAVE_FF == 0) ? valid_reg : valid_i;

endmodule

// Convert to Signed (CVT) - stage 4
/*
 * We want to convert both to signed to prepare it for the addition step.
 * [ + ] - FRAC_WIDTH
 *
 */
module cvt #(
    parameter EXP_WIDTH = 0,
    parameter FRAC_WIDTH = 0,
    parameter SAVE_FF = 0,
    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter FRAC_EX_WIDTH = 1 + 1 + FRAC_WIDTH + 1,
    parameter FRAC_EX_IDX_LSB = 0,
    parameter FRAC_EX_IDX_MSB = FRAC_EX_WIDTH + FRAC_EX_IDX_LSB - 1,
    parameter EXP_IDX_LSB = FRAC_EX_WIDTH,
    parameter EXP_IDX_MSB = EXP_WIDTH + EXP_IDX_LSB - 1,
    parameter SIGN_IDX = EXP_WIDTH + FRAC_EX_WIDTH,
    parameter FP_WIDTH_TOT = 1 + EXP_WIDTH + FRAC_EX_WIDTH
) (
    input clk_i,
    input rst_i,

    input  [FP_WIDTH_TOT - 1 : 0] fp_a_i,
    input  [FP_WIDTH_TOT - 1 : 0] fp_b_i,
    input                         valid_i,

    output [FP_WIDTH_TOT - 1 : 0] fp_a_o,
    output [FP_WIDTH_TOT - 1 : 0] fp_b_o,
    output                        valid_o
);

    ////////////////////////////////////////////////////////////////
    // Input Registers
    logic [FP_WIDTH_TOT - 1 : 0] fp_a_reg;
    logic [FP_WIDTH_TOT - 1 : 0] fp_b_reg;
    logic                        valid_reg;

    always_ff @(posedge clk_i) begin
        if(SAVE_FF == 0) begin
            fp_a_reg     <= fp_a_i;
            fp_b_reg     <= fp_b_i;
            if(rst_i) begin
                valid_reg <= 0;
            end else begin
                valid_reg <= valid_i;
            end
        end
    end

    ////////////////////////////////////////////////////////////////
    // Main
    logic                         fp_a_sign;
    logic [EXP_WIDTH - 1 : 0]     fp_a_exp;
    logic [FRAC_EX_WIDTH - 1 : 0] fp_a_frac_ex;

    logic                         fp_b_sign;
    logic [EXP_WIDTH - 1 : 0]     fp_b_exp;
    logic [FRAC_EX_WIDTH - 1 : 0] fp_b_frac_ex;

    always_comb begin
        if(SAVE_FF == 0) begin
            fp_a_sign    = fp_a_reg[SIGN_IDX];
            fp_a_exp     = fp_a_reg[EXP_IDX_MSB : EXP_IDX_LSB];
            fp_a_frac_ex = fp_a_reg[FRAC_EX_IDX_MSB : FRAC_EX_IDX_LSB];

            fp_b_sign    = fp_b_reg[SIGN_IDX];
            fp_b_exp     = fp_b_reg[EXP_IDX_MSB : EXP_IDX_LSB];
            fp_b_frac_ex = fp_b_reg[FRAC_EX_IDX_MSB : FRAC_EX_IDX_LSB];

            if(fp_a_sign != fp_b_sign) begin
                if(fp_a_sign) begin
                    fp_a_frac_ex = ~fp_a_frac_ex + 1;
                end else begin
                    fp_b_frac_ex = ~fp_b_frac_ex + 1;
                end
            end
        end else begin
            fp_a_sign    = fp_a_i[SIGN_IDX];
            fp_a_exp     = fp_a_i[EXP_IDX_MSB : EXP_IDX_LSB];
            fp_a_frac_ex = fp_a_i[FRAC_EX_IDX_MSB : FRAC_EX_IDX_LSB];

            fp_b_sign    = fp_b_i[SIGN_IDX];
            fp_b_exp     = fp_b_i[EXP_IDX_MSB : EXP_IDX_LSB];
            fp_b_frac_ex = fp_b_i[FRAC_EX_IDX_MSB : FRAC_EX_IDX_LSB];

            if(fp_a_sign != fp_b_sign) begin
                if(fp_a_sign) begin
                    fp_a_frac_ex = ~fp_a_frac_ex + 1;
                end else begin
                    fp_b_frac_ex = ~fp_b_frac_ex + 1;
                end
            end
        end
    end

    ////////////////////////////////////////////////////////////////
    // Output
    assign fp_a_o  = {fp_a_sign, fp_a_exp, fp_a_frac_ex};
    assign fp_b_o  = {fp_b_sign, fp_b_exp, fp_b_frac_ex};
    assign valid_o = (SAVE_FF == 0) ? valid_reg : valid_i;
endmodule

// Add Values Together (AVT) - stage 5
/* Now that the two values are on the same order of magnitudes, and both
 * signed, we can add them together. 
 * [ + ] - FRAC_WIDTH
 */
module avt #(
    parameter EXP_WIDTH = 0,
    parameter FRAC_WIDTH = 0,
    parameter SAVE_FF = 0,
    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter FRAC_EX_WIDTH = 1 + 1 + FRAC_WIDTH + 1,
    parameter FRAC_EX_IDX_LSB = 0,
    parameter FRAC_EX_IDX_MSB = FRAC_EX_WIDTH + FRAC_EX_IDX_LSB - 1,
    parameter EXP_IDX_LSB = FRAC_EX_WIDTH,
    parameter EXP_IDX_MSB = EXP_WIDTH + EXP_IDX_LSB - 1,
    parameter SIGN_IDX = EXP_WIDTH + FRAC_EX_WIDTH,
    parameter FP_WIDTH_TOT = 1 + EXP_WIDTH + FRAC_EX_WIDTH
) (
    input clk_i,
    input rst_i,

    input  [FP_WIDTH_TOT - 1 : 0] fp_a_i,
    input  [FP_WIDTH_TOT - 1 : 0] fp_b_i,
    input                         valid_i,

    output [FP_WIDTH_TOT - 1 : 0] fp_o,
    output                        fp_a_sign_o,
    output                        fp_b_sign_o,
    output                        valid_o
);

    ////////////////////////////////////////////////////////////////
    // Input Registers
    logic [FP_WIDTH_TOT - 1 : 0] fp_a_reg;
    logic [FP_WIDTH_TOT - 1 : 0] fp_b_reg;
    logic                        valid_reg;

    always_ff @(posedge clk_i) begin
        if(SAVE_FF == 0) begin
            fp_a_reg     <= fp_a_i;
            fp_b_reg     <= fp_b_i;
            if(rst_i) begin
                valid_reg <= 0;
            end else begin
                valid_reg <= valid_i;
            end
        end
    end

    ////////////////////////////////////////////////////////////////
    // Main
    logic                         fp_a_sign;
    logic [EXP_WIDTH - 1 : 0]     fp_a_exp;
    logic [FRAC_EX_WIDTH - 1 : 0] fp_a_frac_ex;

    logic                         fp_b_sign;
    logic [EXP_WIDTH - 1 : 0]     fp_b_exp;
    logic [FRAC_EX_WIDTH - 1 : 0] fp_b_frac_ex;

    logic                         fp_sign;
    logic [EXP_WIDTH - 1 : 0]     fp_exp;
    logic [FRAC_EX_WIDTH - 1 : 0] fp_frac_ex;

    always_comb begin
        if(SAVE_FF == 0) begin
            fp_a_sign    = fp_a_reg[SIGN_IDX];
            fp_a_exp     = fp_a_reg[EXP_IDX_MSB : EXP_IDX_LSB];
            fp_a_frac_ex = fp_a_reg[FRAC_EX_IDX_MSB : FRAC_EX_IDX_LSB];

            fp_b_sign    = fp_b_reg[SIGN_IDX];
            fp_b_exp     = fp_b_reg[EXP_IDX_MSB : EXP_IDX_LSB];
            fp_b_frac_ex = fp_b_reg[FRAC_EX_IDX_MSB : FRAC_EX_IDX_LSB];

            fp_sign      = 0;
            fp_exp       = fp_a_exp;
            fp_frac_ex  = 0;

            fp_frac_ex = fp_a_frac_ex + fp_b_frac_ex;
        end else begin
            fp_a_sign    = fp_a_i[SIGN_IDX];
            fp_a_exp     = fp_a_i[EXP_IDX_MSB : EXP_IDX_LSB];
            fp_a_frac_ex = fp_a_i[FRAC_EX_IDX_MSB : FRAC_EX_IDX_LSB];

            fp_b_sign    = fp_b_i[SIGN_IDX];
            fp_b_exp     = fp_b_i[EXP_IDX_MSB : EXP_IDX_LSB];
            fp_b_frac_ex = fp_b_i[FRAC_EX_IDX_MSB : FRAC_EX_IDX_LSB];

            fp_sign      = 0;
            fp_exp       = fp_a_exp;
            fp_frac_ex  = 0;

            fp_frac_ex = fp_a_frac_ex + fp_b_frac_ex;
        end
    end

    ////////////////////////////////////////////////////////////////
    // Output
    assign fp_o        = {fp_sign, fp_exp, fp_frac_ex};
    assign fp_a_sign_o = fp_a_sign;
    assign fp_b_sign_o = fp_b_sign;
    assign valid_o     = (SAVE_FF == 0) ? valid_reg : valid_i;
endmodule

// Convet to Unsigned (CVU) - stage 6
/* The result is signed, we need to convert it to unsigned. This can
 * be done with some careful consideration about the sign bits as that
 * that will determine whether to interpret the carry bit as actually
 * a carry bit or the sign bit
 * [ + ] - FRAC_WIDTH
 */
module cvu #(
    parameter EXP_WIDTH = 0,
    parameter FRAC_WIDTH = 0,
    parameter SAVE_FF = 0,
    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter FRAC_EX_WIDTH = 1 + 1 + FRAC_WIDTH + 1,
    parameter FRAC_EX_IDX_LSB = 0,
    parameter FRAC_EX_IDX_MSB = FRAC_EX_WIDTH + FRAC_EX_IDX_LSB - 1,
    parameter EXP_IDX_LSB = FRAC_EX_WIDTH,
    parameter EXP_IDX_MSB = EXP_WIDTH + EXP_IDX_LSB - 1,
    parameter SIGN_IDX = EXP_WIDTH + FRAC_EX_WIDTH,
    parameter FP_WIDTH_TOT = 1 + EXP_WIDTH + FRAC_EX_WIDTH,
    parameter CARRY_IDX = 1 + FRAC_WIDTH + 1
) (
    input clk_i,
    input rst_i,

    input  [FP_WIDTH_TOT - 1 : 0] fp_i,
    input                         fp_a_sign_i,
    input                         fp_b_sign_i,
    input                         valid_i,

    output [FP_WIDTH_TOT - 1 : 0] fp_o,
    output                        valid_o
);
    ////////////////////////////////////////////////////////////////
    // Input Registers
    logic [FP_WIDTH_TOT - 1 : 0] fp_reg;
    logic                        fp_a_sign_reg;
    logic                        fp_b_sign_reg;
    logic                        valid_reg;

    always_ff @(posedge clk_i) begin
        if(SAVE_FF == 0) begin
            fp_reg        <= fp_i;
            fp_a_sign_reg <= fp_a_sign_i;
            fp_b_sign_reg <= fp_b_sign_i;
            if(rst_i) begin
                valid_reg <= 0;
            end else begin
                valid_reg <= valid_i;
            end
        end
    end

    ////////////////////////////////////////////////////////////////
    // Main
    logic                         fp_sign;
    logic [EXP_WIDTH - 1 : 0]     fp_exp;
    logic [FRAC_EX_WIDTH - 1 : 0] fp_frac_ex;
    
    always_comb begin
        if(SAVE_FF == 0) begin
            fp_sign    = fp_reg[SIGN_IDX];
            fp_exp     = fp_reg[EXP_IDX_MSB : EXP_IDX_LSB];
            fp_frac_ex = fp_reg[FRAC_EX_IDX_MSB : FRAC_EX_IDX_LSB];

            if(fp_a_sign_reg != fp_b_sign_reg) begin
                if(fp_frac_ex[CARRY_IDX]) begin 
                    fp_frac_ex = ~fp_frac_ex + 1;
                    fp_sign = 1;
                end else begin
                    fp_sign = 0;
                end
            end else begin
                fp_sign = fp_a_sign_reg;
            end

            if(fp_frac_ex == 0) fp_exp = 0;
        end else begin
            fp_sign    = fp_i[SIGN_IDX];
            fp_exp     = fp_i[EXP_IDX_MSB : EXP_IDX_LSB];
            fp_frac_ex = fp_i[FRAC_EX_IDX_MSB : FRAC_EX_IDX_LSB];

            if(fp_a_sign_i != fp_b_sign_i) begin
                if(fp_frac_ex[CARRY_IDX]) begin 
                    fp_frac_ex = ~fp_frac_ex + 1;
                    fp_sign = 1;
                end else begin
                    fp_sign = 0;
                end
            end else begin
                fp_sign = fp_a_sign_i;
            end

            if(fp_frac_ex == 0) fp_exp = 0;
        end
    end

    ////////////////////////////////////////////////////////////////
    // Output
    assign fp_o    = {fp_sign, fp_exp, fp_frac_ex};
    assign valid_o = (SAVE_FF == 0) ? valid_reg : valid_i;
endmodule

// Normalize Results (NR) - stage 7
/* We need to take the result and normalize it. This is also
 * a variable shifter depending on where the first 1 value is
 * found. If the frac bits turn out to be 0, set output exponent
 * also to 0. If exponent underflow, set to 0, if exponent overflow,
 * set to max value.
 * [variable shifter, either 1 right or multiple left]
 * [ < ] - EXP_WIDTH
 * [ + ] - EXP_WIDTH
 *
 */
module nr #(
    parameter EXP_WIDTH = 0,
    parameter FRAC_WIDTH = 0,
    parameter SAVE_FF = 0,
    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter FRAC_EX_WIDTH = 1 + 1 + FRAC_WIDTH + 1,
    parameter FRAC_EX_IDX_LSB = 0,
    parameter FRAC_EX_IDX_MSB = FRAC_EX_WIDTH + FRAC_EX_IDX_LSB - 1,
    parameter EXP_IDX_LSB = FRAC_EX_WIDTH,
    parameter EXP_IDX_MSB = EXP_WIDTH + EXP_IDX_LSB - 1,
    parameter SIGN_IDX = EXP_WIDTH + FRAC_EX_WIDTH,
    parameter FP_WIDTH_TOT = 1 + EXP_WIDTH + FRAC_EX_WIDTH,
    parameter CARRY_IDX = 1 + FRAC_WIDTH + 1,
    parameter LEAD_IDX = FRAC_WIDTH + 1,
    parameter EXP_MAX = (2**EXP_WIDTH) - 1
) (
    input clk_i,
    input rst_i,

    input  [FP_WIDTH_TOT - 1 : 0] fp_i,
    input                         valid_i,

    output [FP_WIDTH_TOT - 1 : 0] fp_o,
    output                        valid_o
);
    ////////////////////////////////////////////////////////////////
    // Input Registers
    logic [FP_WIDTH_TOT - 1 : 0] fp_reg;
    logic                        valid_reg;

    always_ff @(posedge clk_i) begin
        if(SAVE_FF == 0) begin
            fp_reg        <= fp_i;
            if(rst_i) begin
                valid_reg <= 0;
            end else begin
                valid_reg <= valid_i;
            end
        end
    end

    ////////////////////////////////////////////////////////////////
    // Main
    logic                                  fp_sign;
    logic unsigned [EXP_WIDTH - 1 : 0]     fp_exp;
    logic unsigned [EXP_WIDTH - 1 : 0]     fp_exp_const;
    logic          [FRAC_EX_WIDTH - 1 : 0] fp_frac_ex;
    logic          [FRAC_EX_WIDTH - 1 : 0] fp_frac_ex_const;

    logic unsigned [EXP_WIDTH - 1 : 0] shift;
    logic signed   [EXP_WIDTH     : 0] diff;


    always_comb begin
        if(SAVE_FF == 0) begin
            fp_sign    = fp_reg[SIGN_IDX];
            fp_exp     = fp_reg[EXP_IDX_MSB : EXP_IDX_LSB];
            fp_frac_ex = fp_reg[FRAC_EX_IDX_MSB : FRAC_EX_IDX_LSB];

            fp_exp_const = fp_exp[EXP_WIDTH - 1 : 0];
            fp_frac_ex_const = fp_frac_ex;

            shift = 0;
            for(int i = 0; i <= LEAD_IDX; i++) begin
                if(fp_frac_ex_const[i]) begin
                    shift = LEAD_IDX - i;
                end
            end
            diff = fp_exp_const - shift;

            if(fp_frac_ex_const[CARRY_IDX]) begin
                fp_frac_ex = fp_frac_ex_const >> 1;
                fp_exp = fp_exp_const + 1;
            end else begin
                if(diff > 0) begin
                    fp_frac_ex = fp_frac_ex_const << shift;
                    fp_exp = fp_exp_const - shift;
                end else begin
                    fp_frac_ex = 0;
                    fp_exp = 0;
                end
            end

            if(fp_exp_const == EXP_MAX) begin
                fp_exp = EXP_MAX;
            end

        end else begin
            fp_sign    = fp_i[SIGN_IDX];
            fp_exp     = fp_i[EXP_IDX_MSB : EXP_IDX_LSB];
            fp_frac_ex = fp_i[FRAC_EX_IDX_MSB : FRAC_EX_IDX_LSB];

            fp_exp_const = fp_exp[EXP_WIDTH - 1 : 0];
            fp_frac_ex_const = fp_frac_ex;

            shift = 0;
            for(int i = 0; i <= LEAD_IDX; i++) begin
                if(fp_frac_ex_const[i]) begin
                    shift = LEAD_IDX - i;
                end
            end
            diff = fp_exp_const - shift;

            if(fp_frac_ex_const[CARRY_IDX]) begin
                fp_frac_ex = fp_frac_ex_const >> 1;
                fp_exp = fp_exp_const + 1;
            end else begin
                if(diff > 0) begin
                    fp_frac_ex = fp_frac_ex_const << shift;
                    fp_exp = fp_exp_const - shift;
                end else begin
                    fp_frac_ex = 0;
                    fp_exp = 0;
                end
            end

            if(fp_exp_const == EXP_MAX) begin
                fp_exp = EXP_MAX;
            end
        end
    end
    ////////////////////////////////////////////////////////////////
    // Output
    assign fp_o    = {fp_sign, fp_exp, fp_frac_ex};
    assign valid_o = (SAVE_FF == 0) ? valid_reg : valid_i;
endmodule

// Normalize Results Same Sign (NR) - stage 7
/* Knowing that both values are of the same sign we can skip
 * having a priority encoder + variable shifter and instead
 * just check the carry bit and for 0!
 * [ < ] - EXP_WIDTH
 * [ + ] - EXP_WIDTH
 *
 */
module nrss #(
    parameter EXP_WIDTH = 0,
    parameter FRAC_WIDTH = 0,
    parameter SAVE_FF = 0,
    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter FRAC_EX_WIDTH = 1 + 1 + FRAC_WIDTH + 1,
    parameter FRAC_EX_IDX_LSB = 0,
    parameter FRAC_EX_IDX_MSB = FRAC_EX_WIDTH + FRAC_EX_IDX_LSB - 1,
    parameter EXP_IDX_LSB = FRAC_EX_WIDTH,
    parameter EXP_IDX_MSB = EXP_WIDTH + EXP_IDX_LSB - 1,
    parameter SIGN_IDX = EXP_WIDTH + FRAC_EX_WIDTH,
    parameter FP_WIDTH_TOT = 1 + EXP_WIDTH + FRAC_EX_WIDTH,
    parameter CARRY_IDX = 1 + FRAC_WIDTH + 1,
    parameter LEAD_IDX = FRAC_WIDTH + 1,
    parameter EXP_MAX = (2**EXP_WIDTH) - 1
) (
    input clk_i,
    input rst_i,

    input  [FP_WIDTH_TOT - 1 : 0] fp_i,
    input                         valid_i,

    output [FP_WIDTH_TOT - 1 : 0] fp_o,
    output                        valid_o
);
    ////////////////////////////////////////////////////////////////
    // Input Registers
    logic [FP_WIDTH_TOT - 1 : 0] fp_reg;
    logic                        valid_reg;

    always_ff @(posedge clk_i) begin
        if(SAVE_FF == 0) begin
            fp_reg        <= fp_i;
            if(rst_i) begin
                valid_reg <= 0;
            end else begin
                valid_reg <= valid_i;
            end
        end
    end

    ////////////////////////////////////////////////////////////////
    // Main
    logic                                  fp_sign;
    logic unsigned [EXP_WIDTH - 1 : 0]     fp_exp;
    logic unsigned [EXP_WIDTH - 1 : 0]     fp_exp_const;
    logic          [FRAC_EX_WIDTH - 1 : 0] fp_frac_ex;
    logic          [FRAC_EX_WIDTH - 1 : 0] fp_frac_ex_const;

    always_comb begin
        if(SAVE_FF == 0) begin
            fp_sign    = fp_reg[SIGN_IDX];
            fp_exp     = fp_reg[EXP_IDX_MSB : EXP_IDX_LSB];
            fp_frac_ex = fp_reg[FRAC_EX_IDX_MSB : FRAC_EX_IDX_LSB];

            fp_exp_const = fp_exp[EXP_WIDTH - 1 : 0];
            fp_frac_ex_const = fp_frac_ex;

            if(fp_frac_ex_const[CARRY_IDX]) begin
                fp_frac_ex = fp_frac_ex_const >> 1;
                fp_exp = fp_exp_const + 1;
            end else if(fp_frac_ex_const == 0) begin
                fp_frac_ex = 0;
                fp_exp = 0;
            end

            if(fp_exp_const == EXP_MAX) begin
                fp_exp = EXP_MAX;
            end
        end else begin
            fp_sign    = fp_i[SIGN_IDX];
            fp_exp     = fp_i[EXP_IDX_MSB : EXP_IDX_LSB];
            fp_frac_ex = fp_i[FRAC_EX_IDX_MSB : FRAC_EX_IDX_LSB];

            fp_exp_const = fp_exp[EXP_WIDTH - 1 : 0];
            fp_frac_ex_const = fp_frac_ex;

            if(fp_frac_ex_const[CARRY_IDX]) begin
                fp_frac_ex = fp_frac_ex_const >> 1;
                fp_exp = fp_exp_const + 1;
            end else if(fp_frac_ex_const == 0) begin
                fp_frac_ex = 0;
                fp_exp = 0;
            end

            if(fp_exp_const == EXP_MAX) begin
                fp_exp = EXP_MAX;
            end
        end
    end
    ////////////////////////////////////////////////////////////////
    // Output
    assign fp_o    = {fp_sign, fp_exp, fp_frac_ex};
    assign valid_o = (SAVE_FF == 0) ? valid_reg : valid_i;
endmodule


// Round Results (RR) - stage 8
/* Finally, using the round bit, round the results.
 * In this case an overflow could happen which would cause the exponent to increase by 1.
 * Which means we would also have to check exponent overflow, can only happen if the exponent
 * is already at max value.
 * [ + ] - FRAC_WIDTH
 * [ < ] - EXP_WIDTH
 * [ + ] - EXP_WIDTH
 */
module rr #(
    parameter EXP_WIDTH = 0,
    parameter FRAC_WIDTH = 0,
    parameter SAVE_FF = 0,
    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter FRAC_EX_WIDTH = 1 + 1 + FRAC_WIDTH + 1,
    parameter FRAC_EX_IDX_LSB = 0,
    parameter FRAC_EX_IDX_MSB = FRAC_EX_WIDTH + FRAC_EX_IDX_LSB - 1,
    parameter FRAC_IDX_LSB = 1,
    parameter FRAC_IDX_MSB = FRAC_WIDTH + FRAC_IDX_LSB - 1,
    parameter EXP_IDX_LSB = FRAC_EX_WIDTH,
    parameter EXP_IDX_MSB = EXP_WIDTH + EXP_IDX_LSB - 1,
    parameter SIGN_IDX = EXP_WIDTH + FRAC_EX_WIDTH,
    parameter ROUND_IDX = 0,
    parameter CARRY_IDX = 1 + FRAC_WIDTH + 1,
    parameter FP_WIDTH_TOT = 1 + EXP_WIDTH + FRAC_EX_WIDTH,
    parameter FP_WIDTH_REG = 1 + EXP_WIDTH + FRAC_WIDTH,
    parameter EXP_MAX = (2**EXP_WIDTH) - 1
) (
    input clk_i,
    input rst_i,

    input  [FP_WIDTH_TOT - 1 : 0] fp_i,
    input                         valid_i,

    output [FP_WIDTH_REG - 1 : 0] fp_o,
    output                        valid_o
);
    ////////////////////////////////////////////////////////////////
    // Input Registers
    logic [FP_WIDTH_TOT - 1 : 0] fp_reg;
    logic                        valid_reg;

    always_ff @(posedge clk_i) begin
        if(SAVE_FF == 0) begin
            fp_reg        <= fp_i;
            if(rst_i) begin
                valid_reg <= 0;
            end else begin
                valid_reg <= valid_i;
            end
        end
    end

    ////////////////////////////////////////////////////////////////
    // Main
    logic                                  fp_sign;
    logic unsigned [EXP_WIDTH - 1 : 0]     fp_exp;
    logic unsigned [EXP_WIDTH - 1 : 0]     fp_exp_const;
    logic          [FRAC_EX_WIDTH - 1 : 0] fp_frac_ex;
    

    always_comb begin
        if(SAVE_FF == 0) begin
            fp_sign    = fp_reg[SIGN_IDX];
            fp_exp     = fp_reg[EXP_IDX_MSB : EXP_IDX_LSB];
            fp_frac_ex = fp_reg[FRAC_EX_IDX_MSB : FRAC_EX_IDX_LSB];

            fp_exp_const = fp_exp[EXP_WIDTH - 1 : 0];
        
            if(fp_frac_ex[ROUND_IDX]) begin
                fp_frac_ex = fp_frac_ex + 1; 
            end

            if(fp_frac_ex[CARRY_IDX]) begin
                fp_frac_ex = fp_frac_ex >> 1;
                fp_exp = fp_exp + 1;
            end

            if(fp_exp_const == EXP_MAX) fp_exp = EXP_MAX;
        end else begin
            fp_sign    = fp_i[SIGN_IDX];
            fp_exp     = fp_i[EXP_IDX_MSB : EXP_IDX_LSB];
            fp_frac_ex = fp_i[FRAC_EX_IDX_MSB : FRAC_EX_IDX_LSB];

            fp_exp_const = fp_exp[EXP_WIDTH - 1 : 0];
        
            if(fp_frac_ex[ROUND_IDX]) begin
                fp_frac_ex = fp_frac_ex + 1; 
            end

            if(fp_frac_ex[CARRY_IDX]) begin
                fp_frac_ex = fp_frac_ex >> 1;
                fp_exp = fp_exp + 1;
            end

            if(fp_exp_const == EXP_MAX) fp_exp = EXP_MAX;
        end
    end

    ////////////////////////////////////////////////////////////////
    // Output
    assign fp_o    = {fp_sign, fp_exp, fp_frac_ex[FRAC_IDX_MSB : FRAC_IDX_LSB]};
    assign valid_o = (SAVE_FF == 0) ? valid_reg : valid_i;
endmodule




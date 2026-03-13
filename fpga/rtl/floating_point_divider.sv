/* Floating Point Divider
 * Follows the IEEE 754 specification (almost) but has been parameterized
 * so that you can adjust how many exponent bits and fraction bits
 * you want.
 *
 * The exception is subnormal values are approximated to zero. In particular,
 * the divider can accept subnormal values, but it will treat it as a 0
 * (the fractional bits will be set to 0). The reasoning is that
 * the cost in hardware isn't worth the 'gradual' descent into subnormal,
 * if even smaller values are required, use more exponent bits. Adding
 * a single exponent bit expands the range by 2^2^x.
 * The total number of bits including the sign bit is
 * 1 + EXP_WIDTH + FRAC_WIDTH.
 *
 * By doing so, this guarantees that the lead bits of the divided numbers are
 * either are 1, or just 0 (with fractional bits being zero). This minimizes
 * any amount of shifting as the smallest value produced would only have
 * to be shift once (not including x/0, 0/x and 0/0 whic have to be handled)
 *
 * Similar to multiplier, it is possible for a result to be exactly
 * at EXP_MAX, but the left shift would make it a valid number since 
 * the exponent would decrease by one. My divider doesn't deal with 
 * this. In summary, if the intermediary result goes to infinity,
 * it stays at infinity even if such a case would bring it back.
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
 */


module floating_point_divider #(
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
    parameter FP_WIDTH_TOT = 1 + EXP_WIDTH + 1 + 1 + FRAC_WIDTH + 1,
    parameter FRAC_EX_WIDTH = 1 + 1 + FRAC_WIDTH + 1,
    parameter FRAC_EX_MULT_WIDTH = 2 * FRAC_EX_WIDTH,
    parameter BIAS = 2**(EXP_WIDTH - 1) - 1,
    parameter EXP_MAX = 2**EXP_WIDTH - 1,
    parameter FRAC_DIV_WIDTH = FRAC_EX_WIDTH + 2

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

    logic                                   fp_a_sign;
    logic unsigned [EXP_WIDTH - 1 : 0]      fp_a_exp;
    logic signed   [EXP_WIDTH + 2 - 1 : 0]  fp_a_exp_s;
    logic                                   fp_a_carry;
    logic                                   fp_a_lead;
    logic          [FRAC_WIDTH - 1 : 0]     fp_a_frac;
    logic                                   fp_a_round;
    logic unsigned [FRAC_EX_WIDTH - 1 : 0]  fp_a_frac_ex;
    logic          [FRAC_DIV_WIDTH - 1 : 0] fp_a_frac_div;
    logic                                   fp_a_zero;

    logic                                   fp_b_sign;
    logic unsigned [EXP_WIDTH - 1 : 0]      fp_b_exp;
    logic signed   [EXP_WIDTH + 2 - 1 : 0]  fp_b_exp_s;
    logic                                   fp_b_carry;
    logic                                   fp_b_lead;
    logic          [FRAC_WIDTH - 1 : 0]     fp_b_frac;
    logic                                   fp_b_round;
    logic unsigned [FRAC_EX_WIDTH - 1 : 0]  fp_b_frac_ex;
    logic          [FRAC_DIV_WIDTH - 1 : 0] fp_b_frac_div;
    logic                                   fp_b_zero;

    logic signed   [EXP_WIDTH + 2 - 1 : 0]  fp_exp_s;
    logic                                   fp_sign;
    logic unsigned [EXP_WIDTH - 1 : 0]      fp_exp;
    logic          [FRAC_EX_WIDTH - 1 : 0]  fp_frac_ex;
    logic          [FRAC_DIV_WIDTH - 1 : 0] fp_quotient_start;    

    ////////////////////////////////////////////////////////////////
    // Entry
    always_comb begin
        fp_a_sign  = fp_a_reg[SIGN_IDX];
        fp_a_exp   = fp_a_reg[EXP_IDX_MSB : EXP_IDX_LSB];
        fp_a_carry = 0;
        fp_a_lead  = 1;
        fp_a_frac  = fp_a_reg[FRAC_IDX_MSB : FRAC_IDX_LSB];
        fp_a_round = 0;
        fp_a_zero  = 0;

        fp_b_sign  = fp_b_reg[SIGN_IDX];
        fp_b_exp   = fp_b_reg[EXP_IDX_MSB : EXP_IDX_LSB];
        fp_b_carry = 0;
        fp_b_lead  = 1;
        fp_b_frac  = fp_b_reg[FRAC_IDX_MSB : FRAC_IDX_LSB];
        fp_b_round = 0;
        fp_b_zero  = 0;
    
        if(fp_a_exp == 0) begin 
            fp_a_lead = 0;
            fp_a_frac = 0;
            fp_a_exp = 1;
            fp_a_zero = 1;
        end 
        if(fp_b_exp == 0) begin 
            fp_b_lead = 0;
            fp_b_frac = 0;
            fp_b_exp = 1;
            fp_b_zero = 1;
        end

        // setting frac_ex
        fp_a_frac_ex = {fp_a_carry, fp_a_lead, fp_a_frac, fp_a_round};
        fp_a_frac_div = {1'b0, fp_a_frac_ex, 1'b0};
        fp_b_frac_ex = {fp_b_carry, fp_b_lead, fp_b_frac, fp_b_round};
        fp_b_frac_div = {1'b0, fp_b_frac_ex, 1'b0};
        fp_quotient_start = 0;

        // exponent calculations
        fp_a_exp_s = {2'b00, fp_a_exp};
        fp_b_exp_s = {2'b00, fp_b_exp};

        fp_a_exp_s = fp_a_exp_s - BIAS;
        fp_b_exp_s = fp_b_exp_s - BIAS;

        fp_exp_s = fp_a_exp_s - fp_b_exp_s;
        if(fp_exp_s <= (-BIAS)) begin
            fp_exp_s = -BIAS;
        end else if (fp_exp_s >= (BIAS + 1)) begin
            fp_exp_s = BIAS + 1;
        end

        if((fp_a_exp == EXP_MAX) || (fp_b_exp == EXP_MAX)) begin
            fp_exp_s = BIAS + 1;
        end

        fp_sign    = fp_a_sign ^ fp_b_sign;
        fp_exp_s   = fp_exp_s + BIAS;
        fp_exp     = fp_exp_s[EXP_WIDTH - 1 : 0];

    end

    ////////////////////////////////////////////////////////////////
    // Divisor Parts and Pipelining values
    logic                     fp_sign_pipe  [FRAC_EX_WIDTH];
    logic [EXP_WIDTH - 1 : 0] fp_exp_pipe   [FRAC_EX_WIDTH];
    logic                     fp_a_zero_pipe[FRAC_EX_WIDTH];
    logic                     fp_b_zero_pipe[FRAC_EX_WIDTH];

    always_ff@(posedge clk_i) begin
        fp_sign_pipe  [0] <= fp_sign;
        fp_exp_pipe   [0] <= fp_exp;
        fp_a_zero_pipe[0] <= fp_a_zero;
        fp_b_zero_pipe[0] <= fp_b_zero;
        for(int p = 1; p < FRAC_EX_WIDTH; p++) begin
            fp_sign_pipe  [p] <= fp_sign_pipe  [p-1];
            fp_exp_pipe   [p] <= fp_exp_pipe   [p-1];
            fp_a_zero_pipe[p] <= fp_a_zero_pipe[p-1];
            fp_b_zero_pipe[p] <= fp_b_zero_pipe[p-1];
        end
    end

    logic [FRAC_DIV_WIDTH - 1 : 0] quotient_w [FRAC_EX_WIDTH];
    logic [FRAC_DIV_WIDTH - 1 : 0] dividend_w [FRAC_EX_WIDTH];
    logic [FRAC_DIV_WIDTH - 1 : 0] divisor_w  [FRAC_EX_WIDTH];
    logic                          valid_w    [FRAC_EX_WIDTH];

    generate
        for(genvar d = FRAC_DIV_WIDTH - 3; d >= 0; d--) begin
            // entry
            if(d == (FRAC_DIV_WIDTH - 3)) begin
                divider_part #(
                    .Q_IDX(d),
                    .WIDTH(FRAC_DIV_WIDTH)
                ) div_part (
                    .clk_i(clk_i),
                    .rst_i(rst_i),

                    .quotient_i(fp_quotient_start),
                    .dividend_i(fp_a_frac_div),
                    .divisor_i (fp_b_frac_div),
                    .valid_i   (valid_reg),

                    .quotient_o(quotient_w[FRAC_DIV_WIDTH - 3 - d]), 
                    .dividend_o(dividend_w[FRAC_DIV_WIDTH - 3 - d]),
                    .divisor_o (divisor_w [FRAC_DIV_WIDTH - 3 - d]),
                    .valid_o   (valid_w   [FRAC_DIV_WIDTH - 3 - d])
                );
            end else begin
                divider_part #(
                    .Q_IDX(d),
                    .WIDTH(FRAC_DIV_WIDTH)
                ) div_part (
                    .clk_i(clk_i),
                    .rst_i(rst_i),

                    .quotient_i(quotient_w[FRAC_DIV_WIDTH - 3 - d - 1]),
                    .dividend_i(dividend_w[FRAC_DIV_WIDTH - 3 - d - 1]),
                    .divisor_i (divisor_w [FRAC_DIV_WIDTH - 3 - d - 1]),
                    .valid_i   (valid_w   [FRAC_DIV_WIDTH - 3 - d - 1]),

                    .quotient_o(quotient_w[FRAC_DIV_WIDTH - 3 - d]),
                    .dividend_o(dividend_w[FRAC_DIV_WIDTH - 3 - d]),
                    .divisor_o (divisor_w [FRAC_DIV_WIDTH - 3 - d]),
                    .valid_o   (valid_w   [FRAC_DIV_WIDTH - 3 - d])
                );
            end
        end
    endgenerate

    ////////////////////////////////////////////////////////////////
    // Exit, Shift if necessary, Rounding and checking for Zeros
    logic [FRAC_DIV_WIDTH - 1 : 0] fp_frac_div_result;
    logic [EXP_WIDTH - 1 : 0]      fp_exp_result;

    always_comb begin
        fp_frac_div_result = quotient_w [FRAC_EX_WIDTH - 1];
        fp_exp_result     = fp_exp_pipe [FRAC_EX_WIDTH - 1];

        if(!fp_frac_div_result[FRAC_DIV_WIDTH - 3]) begin
            fp_frac_div_result = fp_frac_div_result << 1;
            if(fp_exp_result != 0) begin
                fp_exp_result = fp_exp_result - 1;
            end
        end 
        
        if(fp_frac_div_result[1]) begin
            fp_frac_div_result = fp_frac_div_result + 2'b10;
            if(fp_frac_div_result[FRAC_DIV_WIDTH - 1]) begin
                fp_frac_div_result = fp_frac_div_result >> 1;
                if(fp_exp_result != EXP_MAX) begin
                    fp_exp_result = fp_exp_result + 1;
                end
            end
        end

        if(fp_exp_result == 0) begin
            fp_frac_div_result = 0;
        end

        if(fp_a_zero_pipe[FRAC_EX_WIDTH - 1] && fp_b_zero_pipe[FRAC_EX_WIDTH - 1]) begin
            fp_exp_result = EXP_MAX;
            fp_frac_div_result = 0;
        end else if (fp_a_zero_pipe[FRAC_EX_WIDTH - 1] && (!fp_b_zero_pipe[FRAC_EX_WIDTH - 1])) begin
            fp_exp_result = 0;
            fp_frac_div_result = 0;
        end else if ((!fp_a_zero_pipe[FRAC_EX_WIDTH - 1]) && fp_b_zero_pipe[FRAC_EX_WIDTH - 1]) begin
            fp_exp_result = EXP_MAX;
            fp_frac_div_result = {FRAC_DIV_WIDTH{1'b1}};
        end 
    end
    assign fp_o = {fp_sign_pipe[FRAC_EX_WIDTH - 1], fp_exp_result, fp_frac_div_result[FRAC_DIV_WIDTH - 3 - 1 : 2]};
    assign valid_o = valid_w[FRAC_EX_WIDTH - 1];
endmodule

module divider_part #(
    parameter Q_IDX = 0,
    parameter WIDTH = 0
) (
    input clk_i,
    input rst_i,

    input  [WIDTH - 1 : 0] quotient_i,
    input  [WIDTH - 1 : 0] dividend_i,
    input  [WIDTH - 1 : 0] divisor_i,
    input                  valid_i,

    output [WIDTH - 1 : 0] quotient_o,
    output [WIDTH - 1 : 0] dividend_o,
    output [WIDTH - 1 : 0] divisor_o,
    output                 valid_o
);
    logic [WIDTH - 1 : 0] quotient_reg;
    logic [WIDTH - 1 : 0] dividend_reg;
    logic [WIDTH - 1 : 0] divisor_reg;
    logic                 valid_reg;

    always_ff@(posedge clk_i) begin
        quotient_reg <= quotient_i;
        dividend_reg <= dividend_i;
        divisor_reg  <= divisor_i;
        if(rst_i) begin
            valid_reg <= 0;
        end else begin
            valid_reg <= valid_i;
        end
    end

    logic unsigned [WIDTH - 1 : 0] dividend;
    logic unsigned [WIDTH - 1 : 0] divisor;
    logic unsigned [WIDTH - 1 : 0] quotient;

    always_comb begin
        dividend = dividend_reg[WIDTH - 1 : 0];
        divisor  = divisor_reg [WIDTH - 1 : 0];
        quotient = quotient_reg[WIDTH - 1 : 0];

        if(dividend >= divisor) begin
            quotient[Q_IDX] = 1;
            dividend = dividend - divisor;
        end else begin
            quotient[Q_IDX] = 0;
        end

        dividend = dividend << 1;
    end

    assign quotient_o = quotient;
    assign dividend_o = dividend;
    assign divisor_o  = divisor;
    assign valid_o    = valid_reg;
endmodule
/*
 * Encapsulates a floating point numbers
 */

class FloatingPoint #(
    parameter EXP_WIDTH = 0,
    parameter FRAC_WIDTH = 0,

    //local
    parameter FP_WIDTH_REG = 1 + EXP_WIDTH + FRAC_WIDTH
);
    logic [FP_WIDTH_REG - 1 : 0] a;
    logic [FP_WIDTH_REG - 1 : 0] b;
    logic [FP_WIDTH_REG - 1 : 0] r;

    function new (logic [FP_WIDTH_REG - 1: 0] a,
                  logic [FP_WIDTH_REG - 1: 0] b,
                  logic [FP_WIDTH_REG - 1: 0] c);
        this.a = a;
        this.b = b;
        this.r = c;
    endfunction
endclass
/*
 * Accepts data stream and inserts zeroes values
 * depending on some condition related to the
 * row and column.
 */

module zero_inserter #(
    parameter EXP_WIDTH,
    parameter FRAC_WIDTH,
    parameter SCALE,
    parameter DISABLE = 0,

    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter FP_WIDTH_REG = 1 + FRAC_WIDTH + EXP_WIDTH

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

    logic [FP_WIDTH_REG - 1 : 0] data;
    logic [15:0]                 col;
    logic [15:0]                 row;
    logic                        valid;

    always@(posedge clk_i) begin
        data <= data_i;
        col  <= col_i;
        row  <= row_i;
        if(rst_i) begin
            valid <= 0; 
        end else begin
            valid <= valid_i;
        end
    end

    logic [FP_WIDTH_REG - 1 : 0] data_zero;
    always_comb begin
        data_zero = 0;
        if(DISABLE == 0) begin
            if(SCALE == 0) begin
                if((row[0] == 0) && (col[0] == 0)) data_zero = data;
            end else if (SCALE == 1) begin
                if((row[1:0] == 0) && (col[1:0] == 0)) data_zero = data;
            end else if (SCALE == 2) begin
                if((row[2:0] == 0) && (col[2:0] == 0)) data_zero = data;
            end
        end else begin
            data_zero = data;
        end
    end

    assign data_o = data_zero;
    assign col_o = col;
    assign row_o = row;
    assign valid_o = valid;
endmodule
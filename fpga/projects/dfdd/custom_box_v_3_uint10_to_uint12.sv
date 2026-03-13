module custom_box_v_3_uint10_to_uint12 (
    input clk_i,
    input rst_i,

    input [9:0]  window_i [3][1],
    input [15:0] col_i,
    input [15:0] row_i,
    input        valid_i,

    output [11:0] data_o,
    output [15:0] col_o,
    output [15:0] row_o,
    output        valid_o

);

    logic [9:0]  window [3][1];
    logic [15:0] col;
    logic [15:0] row;
    logic        valid;

    always@(posedge clk_i) begin
        window <= window_i;
        col    <= col_i;
        row    <= row_i;
        if(rst_i) begin
            valid <= 0;
        end else begin
            valid <= valid_i;
        end
    end

    logic [10:0] level_0 [2];
    logic [11:0] level_1;

    always_comb begin
        level_0[0] = window[0][0] + window[1][0];
        level_0[1] = {1'b0, window[2][0]};

        level_1 = level_0[0] + level_0[1];
    end

    assign data_o  = level_1;
    assign col_o   = col;
    assign row_o   = row;
    assign valid_o = valid;

endmodule
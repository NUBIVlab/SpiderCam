module custom_burt_h_uint12_to_uint16 (
    input clk_i,
    input rst_i,

    input [11:0] window_i [1][5],
    input [15:0] col_i,
    input [15:0] row_i,
    input valid_i,

    output [15:0] data_o,
    output [15:0] col_o,
    output [15:0] row_o,
    output valid_o
);


    logic [11:0] window [1][5];
    logic [15:0] col;
    logic [15:0] row;
    logic valid;

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

    logic [14:0] mult_level [5];

    logic [15:0] level_0 [3];
    logic [16:0] level_1 [2];
    logic [17:0] level_2;

    always_comb begin
        mult_level[0] = window[0][0];          // * 1
        mult_level[1] = window[0][1] << 2;     // * 4
        mult_level[2] = window[0][2] * 3'b110; // * 6
        mult_level[3] = window[0][3] << 2;
        mult_level[4] = window[0][4];

        level_0[0] = mult_level[0] + mult_level[1];
        level_0[1] = mult_level[2] + mult_level[3];
        level_0[2] = {1'b0, mult_level[4]};

        level_1[0] = level_0[0] + level_0[1];
        level_1[1] = {1'b0, level_0[2]};

        level_2 = level_1[0] + level_1[1];
    end

    assign data_o  = level_2[15:0];
    assign col_o   = col;
    assign row_o   = row;
    assign valid_o = valid;


endmodule
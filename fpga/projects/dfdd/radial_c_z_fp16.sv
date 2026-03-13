module radial_c_z_fp16 #(
    parameter NO_ZONES = 1,
    parameter RADIAL_ENABLE = 1
) (
    input clk_i,
    input rst_i,

    input [15:0] data_i,
    input [15:0] confidence_i,
    input [15:0] col_i,
    input [15:0] row_i,
    input        valid_i,

    input [15:0] c_i         [NO_ZONES],
    input [15:0] z_i         [NO_ZONES],
    input [15:0] z_min_i     [NO_ZONES],
    input [17:0] r_squared_i [NO_ZONES],

    input [15:0] col_center_i,
    input [15:0] row_center_i,

    output [15:0] data_o,
    output [15:0] confidence_o,
    output [15:0] col_o,
    output [15:0] row_o,
    output        valid_o
);

    logic [15:0] data;
    logic [15:0] confidence;
    logic [15:0] col;
    logic [15:0] row;
    logic        valid;

    logic [15:0] c         [NO_ZONES];
    logic [15:0] depth     [NO_ZONES];
    logic [15:0] depth_min [NO_ZONES];
    logic [17:0] r_squared [NO_ZONES];

    logic [15:0] col_center;
    logic [15:0] row_center;


    always@(posedge clk_i) begin
        data       <= data_i;
        confidence <= confidence_i;
        col        <= col_i;
        row        <= row_i;

        col_center <= col_center_i;
        row_center <= row_center_i;

        c         <= c_i;
        depth     <= z_i;
        depth_min <= z_min_i;
        r_squared <= r_squared_i;

        if(rst_i) begin
            valid <= 0;
        end else begin
            valid <= valid_i;
        end
    end

    logic signed [15:0] col_s; 
    logic signed [15:0] row_s;

    logic signed [31:0] col_squared;
    logic signed [31:0] row_squared;

    logic [17:0] distance_squared;

    logic [15:0] data_out;
    logic [15:0] confidence_out;

    always_comb begin
        if(RADIAL_ENABLE) begin
        col_s = col;
        row_s = row;

        col_s = col_s - col_center;
        row_s = row_s - row_center;

        col_squared = col_s * col_s;
        row_squared = row_s * row_s;

        distance_squared = col_squared[17:0] + row_squared[17:0];

        data_out        = data;

        for(int z = (NO_ZONES - 1); z >= 0; z--) begin
            if(distance_squared < r_squared_i[z]) begin
                if((confidence < c[z]) || (data > depth[z]) || (data < depth_min[z])) begin
                    data_out = 16'b1111_1111_1111_1111;
                end else begin
                    data_out = data;
                end
            end
        end

        end else begin
            data_out = data;
            if((confidence < c[0]) || (data > depth[0]) || (data < depth_min[0])) begin
                data_out = 16'b1111_1111_1111_1111;
            end
        end

    end

    assign data_o       = data_out;
    assign confidence_o = confidence;
    assign col_o        = col;
    assign row_o        = row;
    assign valid_o      = valid;

endmodule
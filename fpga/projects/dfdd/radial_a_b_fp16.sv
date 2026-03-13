module radial_a_b_fp16 #(
    parameter NO_ZONES = 1
) (
    input [15:0] a_i         [NO_ZONES],
    input [15:0] b_i         [NO_ZONES],
    input [17:0] r_squared_i [NO_ZONES],

    input [15:0] col_i,
    input [15:0] row_i,
    input [15:0] col_center_i,
    input [15:0] row_center_i,

    output [15:0] a_o,
    output [15:0] b_o
);

    logic signed [15:0] col; 
    logic signed [15:0] row;

    logic signed [31:0] col_squared;
    logic signed [31:0] row_squared;

    logic [17:0] distance_squared;

    logic [15:0] a_out;
    logic [15:0] b_out;

    always_comb begin
        col = col_i[15:0];
        row = row_i[15:0];

        col = col - col_center_i;
        row = row - row_center_i;

        col_squared = col * col;
        row_squared = row * row;

        distance_squared = col_squared[17:0] + row_squared[17:0];

        a_out = a_i[0];
        b_out = b_i[0];

        for(int z = (NO_ZONES - 1); z >= 0; z--) begin
            if(distance_squared < r_squared_i[z]) begin
                a_out = a_i[z];
                b_out = b_i[z];
            end
        end
    end

    assign a_o = a_out;
    assign b_o = b_out;
endmodule
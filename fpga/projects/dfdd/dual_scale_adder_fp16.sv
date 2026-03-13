/* Align V/W values coming from 2
 * scales, then accumulate them.
 */

module dual_scale_adder_fp16 #(
    parameter IMAGE_WIDTH,
    parameter IMAGE_HEIGHT,
    parameter BUFFER_DEPTH,

    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter EXP_WIDTH = 5,
    parameter FRAC_WIDTH = 10,
    parameter FP_WIDTH_REG = 1 + FRAC_WIDTH + EXP_WIDTH
) (
    input clk_i,
    input rst_i,

    input  [FP_WIDTH_REG - 1 : 0] v_i     [2],
    input  [FP_WIDTH_REG - 1 : 0] w_i     [2],
    input                         valid_i [2],
    input  [15:0]                 col_i,
    input  [15:0]                 row_i,
    

    output [FP_WIDTH_REG - 1 : 0] v_o,
    output [FP_WIDTH_REG - 1 : 0] w_o,
    output [15:0]                 col_o,
    output [15:0]                 row_o,
    output                        valid_o
);

logic [FP_WIDTH_REG - 1 : 0] v [2];
logic [FP_WIDTH_REG - 1 : 0] w [2];
logic [15:0]                 col;
logic [15:0]                 row;
logic                        valid [2];

always@(posedge clk_i) begin
    v   <= v_i;
    w   <= w_i;
    col <= col_i;
    row <= row_i;
    if(rst_i) begin
        valid[0] <= 0;
        valid[1] <= 0;
    end else begin
        valid[0] <= valid_i[0];
        valid[1] <= valid_i[1];
    end
end

logic                        wr_clks_w     [4];
logic                        wr_rsts_w     [4];
logic [FP_WIDTH_REG - 1 : 0] wr_channels_w [4];
logic                        wr_valids_w   [4];
logic                        wr_sof_w;

assign wr_clks_w     = '{clk_i, clk_i, clk_i, clk_i};
assign wr_rsts_w     = '{rst_i, rst_i, rst_i, rst_i};
assign wr_channels_w = '{v[0], w[0], v[1], w[1]};
assign wr_valids_w   = '{valid[0], valid[0], valid[1], valid[1]};
assign wr_sof_w      =  (valid[0] == 1) && (col == 0) && (row == 0) ? 1 : 0;

logic                        rd_clk_w;
logic                        rd_rst_w;
logic                        rd_stall_w;
logic [FP_WIDTH_REG - 1 : 0] rd_channels_w [4];
logic                        rd_valid_w;
logic                        rd_sof_w;

assign rd_clk_w = clk_i;
assign rd_rst_w = rst_i;
assign rd_stall_w = 0;

stream_buffer #(
    .CHANNELS(4),
    .DATA_WIDTH(FP_WIDTH_REG),
    .BUFFER_DEPTH(BUFFER_DEPTH)
) v_w_aligner (
    .wr_clks_i    (wr_clks_w),
    .wr_rsts_i    (wr_rsts_w),
    .wr_channels_i(wr_channels_w),
    .wr_valids_i  (wr_valids_w),
    .wr_sof_i     (wr_sof_w),
    
    .rd_clk_i     (rd_clk_w),
    .rd_rst_i     (rd_rst_w),
    .rd_stall_i   (rd_stall_w),
    .rd_channels_o(rd_channels_w),
    .rd_valid_o   (rd_valid_w),
    .rd_sof_o     (rd_sof_w)
);

logic [15:0] aligner_col;
logic [15:0] aligner_col_next;
logic [15:0] aligner_col_0;

logic [15:0] aligner_row;
logic [15:0] aligner_row_next;
logic [15:0] aligner_row_0;

always@(posedge clk_i) begin
    if(rst_i) begin
        aligner_col <= 0;
        aligner_row <= 0;
    end else begin
        aligner_col <= aligner_col_next;
        aligner_row <= aligner_row_next;
    end
end

always_comb begin
    aligner_col_next = aligner_col;
    aligner_row_next = aligner_row;
    if(rd_valid_w) begin
        aligner_col_next = aligner_col + 1;
        if(aligner_col == (IMAGE_WIDTH - 1)) begin
            aligner_col_next = 0;
            aligner_row_next = aligner_row + 1;
            if(aligner_row == (IMAGE_HEIGHT - 1)) begin
                aligner_row_next = 0;
            end
        end
    end

    if(rd_sof_w && rd_valid_w) begin
        aligner_col_next = 1;
        aligner_row_next = 0;
    end
end

assign aligner_col_0 = rd_sof_w && rd_valid_w ? 0 : aligner_col;
assign aligner_row_0 = rd_sof_w && rd_valid_w ? 0 : aligner_row;



logic [FP_WIDTH_REG - 1 : 0] acc_kernel_w [1][2];
always_comb begin   
    acc_kernel_w[0][0] = 16'h3c00;
    acc_kernel_w[0][1] = 16'h3c00;
end

logic [FP_WIDTH_REG - 1 : 0] v_adder_data_w [1][2];
logic [FP_WIDTH_REG - 1 : 0] w_adder_data_w [1][2];

assign v_adder_data_w = '{'{rd_channels_w[0], rd_channels_w[2]}};
assign w_adder_data_w = '{'{rd_channels_w[1], rd_channels_w[3]}};

v_w_adder_1_fp16  #(.SAME_SIGN(0)) v_adder (
    .clk_i(clk_i),
    .rst_i(rst_i),

    .window_i(v_adder_data_w),
    .kernel_i(acc_kernel_w),
    .col_i   (aligner_col_0),
    .row_i   (aligner_row_0),
    .valid_i (rd_valid_w),

    .data_o (v_o),
    .col_o  (col_o),
    .row_o  (row_o),
    .valid_o(valid_o)
);

v_w_adder_1_fp16 #(.SAME_SIGN(1)) w_adder (
    .clk_i(clk_i),
    .rst_i(rst_i),

    .window_i(w_adder_data_w),
    .kernel_i(acc_kernel_w),

    .data_o(w_o)
);

endmodule
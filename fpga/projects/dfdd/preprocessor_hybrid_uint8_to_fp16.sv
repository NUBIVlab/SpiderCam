/*
 * Zero'ith scale of DFDD core. Tuned to work with
 * FP16.
 *
 */


module preprocessing_hybrid_uint8_to_fp16 #(
    parameter IMAGE_WIDTH,
    parameter IMAGE_HEIGHT,

    parameter BORDER_ENABLE = 0,
    parameter PREPROCESSING_ENABLE = 1,

    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter EXP_WIDTH = 5,
    parameter FRAC_WIDTH = 10,
    parameter FP_WIDTH_REG = 1 + FRAC_WIDTH + EXP_WIDTH
) (
    input clk_i,
    input rst_i,

    input [7:0]                   i_rho_plus_i,
    input [7:0]                   i_rho_minus_i,
    input [15:0]                  col_i,
    input [15:0]                  row_i,
    input                         valid_i,

    output [FP_WIDTH_REG - 1 : 0] i_a_o,
    output [FP_WIDTH_REG - 1 : 0] i_t_o,
    output [15:0]                 col_o,
    output [15:0]                 row_o,
    output                        valid_o
);  

    // direct if RADIAL_ENABLE == 0
    logic [15:0] i_rho_plus_direct_w;
    logic [15:0] i_rho_minus_direct_w;
    logic [15:0] col_direct_w;
    logic [15:0] row_direct_w;
    logic        valid_direct_w;

    uint8_fp16_converter i_plus_converter (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .uint8_i(i_rho_plus_i),
        .valid_i(valid_i),
        .fp16_o (i_rho_plus_direct_w),
        .valid_o(valid_direct_w)
    );

    uint8_fp16_converter i_minus_converter (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .uint8_i(i_rho_minus_i),
        .valid_i(),
        .fp16_o (i_rho_minus_direct_w),
        .valid_o()
    );

    always@(posedge clk_i) begin
        col_direct_w <= col_i;
        row_direct_w <= row_i;
    end

    ////////////////////////////////////////////////////////////////
    // I rho plus / I rho minus interleaved (for data zipping)
    // I rho plus is at MSB, i rho minus is at LSB
    // row/col maintained by MSB stream at zipped stages (i rho plus)
    //--------------------------------------------
    // processing I_rho_plus / I rho minus (ip / im):
    // _b refers to buffer line
    //
    // window fetcher ip - 1x3
    // box filter horizontal ip 
    // box filter horizontal ip_b 
    //
    // window fetcher im - 1x3
    // box filter horizontal im
    // box filter horizontal im_b
    //--------------------------------------------
    // window fetcher zipped data - 3x1
    // window fetcher zipped data_b - 3x1
    //
    // box filter vertical ip
    // box filter vertical ip_b
    // ip - box(ip) --> ip_br (background removed)
    // window fetcher ip_br - 1x5
    // gaussian horizontal ip_br
    //
    // box filter vertical im
    // box filter vertical im_b
    // ip - box(ip) --> im_br (background removed)
    // window fetcher im_br - 1x5
    // gaussian horizontal im_br
    //--------------------------------------------
    // window fetcher zipped data - 5x1
    //
    // gaussian vertical ip_br
    //
    // gaussian vertical im_br

    logic [7:0]  i_rho_plus_wfh_window_w [1][3];
    logic [15:0] i_rho_plus_wfh_col_w;
    logic [15:0] i_rho_plus_wfh_row_w;
    logic        i_rho_plus_wfh_valid_w;

    window_fetcher #(
        .DATA_WIDTH   (8),
        .IMAGE_WIDTH  (IMAGE_WIDTH),
        .IMAGE_HEIGHT (IMAGE_HEIGHT),
        .WINDOW_WIDTH (3),
        .WINDOW_HEIGHT(1),
        .BORDER_ENABLE(BORDER_ENABLE)
    ) i_rho_plus_window_fetcher_h (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .data_i (i_rho_plus_i),
        .col_i  (col_i),
        .row_i  (row_i),
        .valid_i(valid_i),

        .window_o(i_rho_plus_wfh_window_w),
        .col_o   (i_rho_plus_wfh_col_w),
        .row_o   (i_rho_plus_wfh_row_w),
        .valid_o (i_rho_plus_wfh_valid_w)
    );

    logic [9:0]  i_rho_plus_boxh_data_w;
    logic [7:0]  i_rho_plus_boxh_data_delay_w;
    logic [15:0] i_rho_plus_boxh_col_w;
    logic [15:0] i_rho_plus_boxh_row_w;
    logic        i_rho_plus_boxh_valid_w;
    
    custom_box_h_3_uint8_to_uint10 i_rho_plus_box_h (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .window_i(i_rho_plus_wfh_window_w),
        .col_i   (i_rho_plus_wfh_col_w),
        .row_i   (i_rho_plus_wfh_row_w),
        .valid_i (i_rho_plus_wfh_valid_w),

        .data_o (i_rho_plus_boxh_data_w),
        .col_o  (i_rho_plus_boxh_col_w),
        .row_o  (i_rho_plus_boxh_row_w),
        .valid_o(i_rho_plus_boxh_valid_w)
    );

    always@(posedge clk_i) begin
        i_rho_plus_boxh_data_delay_w <= i_rho_plus_wfh_window_w[0][1];
    end
    
    logic [7:0]  i_rho_minus_wfh_window_w [1][3];
    logic [15:0] i_rho_minus_wfh_col_w;
    logic [15:0] i_rho_minus_wfh_row_w;
    logic        i_rho_minus_wfh_valid_w;

    window_fetcher #(
        .DATA_WIDTH   (8),
        .IMAGE_WIDTH  (IMAGE_WIDTH),
        .IMAGE_HEIGHT (IMAGE_HEIGHT),
        .WINDOW_WIDTH (3),
        .WINDOW_HEIGHT(1),
        .BORDER_ENABLE(BORDER_ENABLE)
    ) i_rho_minus_window_fetcher_h (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .data_i (i_rho_minus_i),
        .col_i  (col_i),
        .row_i  (row_i),
        .valid_i(valid_i),

        .window_o(i_rho_minus_wfh_window_w),
        .col_o   (i_rho_minus_wfh_col_w),
        .row_o   (i_rho_minus_wfh_row_w),
        .valid_o (i_rho_minus_wfh_valid_w)
    );

    logic [9:0]  i_rho_minus_boxh_data_w;
    logic [7:0]  i_rho_minus_boxh_data_delay_w;
    logic [15:0] i_rho_minus_boxh_col_w;
    logic [15:0] i_rho_minus_boxh_row_w;
    logic        i_rho_minus_boxh_valid_w;
    
    custom_box_h_3_uint8_to_uint10 i_rho_minus_box_h (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .window_i(i_rho_minus_wfh_window_w),
        .col_i   (i_rho_minus_wfh_col_w),
        .row_i   (i_rho_minus_wfh_row_w),
        .valid_i (i_rho_minus_wfh_valid_w),

        .data_o (i_rho_minus_boxh_data_w),
        .col_o  (i_rho_minus_boxh_col_w),
        .row_o  (i_rho_minus_boxh_row_w),
        .valid_o(i_rho_minus_boxh_valid_w)
    );

    always@(posedge clk_i) begin
        i_rho_minus_boxh_data_delay_w <= i_rho_minus_wfh_window_w[0][1];
    end

    //--------------------------------------------
    // ------------- zip --------------
    logic [(10 * 2) - 1 : 0] i_rho_boxh_data_w;
    logic [15:0]             i_rho_boxh_col_w;
    logic [15:0]             i_rho_boxh_row_w;
    logic                    i_rho_boxh_valid_w;

    assign i_rho_boxh_data_w  = {i_rho_plus_boxh_data_w, i_rho_minus_boxh_data_w};
    assign i_rho_boxh_col_w   = i_rho_plus_boxh_col_w;
    assign i_rho_boxh_row_w   = i_rho_plus_boxh_row_w;
    assign i_rho_boxh_valid_w = i_rho_plus_boxh_valid_w;

    logic [(10 * 2) - 1 : 0] i_rho_wfv_window_w [3][1];
    logic [15:0]             i_rho_wfv_col_w;
    logic [15:0]             i_rho_wfv_row_w;
    logic                    i_rho_wfv_valid_w;

    logic [10 - 1 : 0] i_rho_plus_wfv_window_w [3][1];
    logic [15:0]       i_rho_plus_wfv_col_w;
    logic [15:0]       i_rho_plus_wfv_row_w;
    logic              i_rho_plus_wfv_valid_w;

    logic [10 - 1 : 0] i_rho_minus_wfv_window_w[3][1];
    logic [15:0]       i_rho_minus_wfv_col_w;
    logic [15:0]       i_rho_minus_wfv_row_w;
    logic              i_rho_minus_wfv_valid_w;

    window_fetcher #(
        .DATA_WIDTH   (10 * 2),
        .IMAGE_WIDTH  (IMAGE_WIDTH),
        .IMAGE_HEIGHT (IMAGE_HEIGHT),
        .WINDOW_WIDTH (1),
        .WINDOW_HEIGHT(3),
        .BORDER_ENABLE(BORDER_ENABLE)
    ) i_rho_window_fetcher_v (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .data_i (i_rho_boxh_data_w),
        .col_i  (i_rho_boxh_col_w),
        .row_i  (i_rho_boxh_row_w),
        .valid_i(i_rho_boxh_valid_w),

        .window_o(i_rho_wfv_window_w),
        .col_o   (i_rho_wfv_col_w),
        .row_o   (i_rho_wfv_row_w),
        .valid_o (i_rho_wfv_valid_w)
    );

    logic [15:0] i_rho_boxh_data_delay_w;
    assign i_rho_boxh_data_delay_w = {i_rho_plus_boxh_data_delay_w, i_rho_minus_boxh_data_delay_w};

    logic [15:0] i_rho_wfv_data_delay_w;

    window_fetcher_z #(
        .DATA_WIDTH(8 * 2),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .WINDOW_WIDTH (1),
        .WINDOW_HEIGHT(3),
        .BORDER_ENABLE(BORDER_ENABLE)
    ) i_rho_window_fetcher_v_delay (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .data_i(i_rho_boxh_data_delay_w),
        .col_i  (i_rho_boxh_col_w),
        .row_i  (i_rho_boxh_row_w),
        .valid_i(i_rho_boxh_valid_w),

        .data_o(i_rho_wfv_data_delay_w)
    );

    // unzip
    always_comb begin
        for(int c = 0; c < 3; c++) begin
            i_rho_plus_wfv_window_w [c][0] = i_rho_wfv_window_w[c][0][(10 * 2) - 1: 10];
            i_rho_minus_wfv_window_w[c][0] = i_rho_wfv_window_w[c][0][10 - 1 : 0];
        end

        i_rho_plus_wfv_col_w   = i_rho_wfv_col_w;
        i_rho_plus_wfv_row_w   = i_rho_wfv_row_w;
        i_rho_plus_wfv_valid_w = i_rho_wfv_valid_w;

        i_rho_minus_wfv_col_w   = i_rho_wfv_col_w;
        i_rho_minus_wfv_row_w   = i_rho_wfv_row_w;
        i_rho_minus_wfv_valid_w = i_rho_wfv_valid_w;

    end

    logic [11:0] i_rho_plus_box_data_w;
    logic [11:0] i_rho_plus_box_data_delay_w;
    logic [15:0] i_rho_plus_box_col_w;
    logic [15:0] i_rho_plus_box_row_w;
    logic        i_rho_plus_box_valid_w;

    custom_box_v_3_uint10_to_uint12 i_rho_plus_box_v (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .window_i(i_rho_plus_wfv_window_w),
        .col_i   (i_rho_plus_wfv_col_w),
        .row_i   (i_rho_plus_wfv_row_w),
        .valid_i (i_rho_plus_wfv_valid_w),

        .data_o (i_rho_plus_box_data_w),
        .col_o  (i_rho_plus_box_col_w),
        .row_o  (i_rho_plus_box_row_w),
        .valid_o(i_rho_plus_box_valid_w)
    );

    ////////////////////////////////////////////////////////////////
    // ip_br = ip - box(ip)

    always@(posedge clk_i) begin
        i_rho_plus_box_data_delay_w <= i_rho_wfv_data_delay_w[15:8] * 4'b1001;
    end 

    logic [12:0] i_rho_plus_box_data_delay_zext_w;
    assign i_rho_plus_box_data_delay_zext_w = {1'b0, i_rho_plus_box_data_delay_w};

    logic [12:0] i_rho_plus_box_data_zext_w;
    assign i_rho_plus_box_data_zext_w = {1'b0, i_rho_plus_box_data_w};

    logic [13:0] i_rho_plus_br_data_w;
    logic [15:0] i_rho_plus_br_col_w;
    logic [15:0] i_rho_plus_br_row_w;
    logic        i_rho_plus_br_valid_w;

    always@(posedge clk_i) begin
        i_rho_plus_br_data_w  <= i_rho_plus_box_data_delay_zext_w - i_rho_plus_box_data_zext_w;
        i_rho_plus_br_col_w   <= i_rho_plus_box_col_w;
        i_rho_plus_br_row_w   <= i_rho_plus_box_row_w;
        i_rho_plus_br_valid_w <= i_rho_plus_box_valid_w;
    end

    logic [13:0] i_rho_plus_box_wfh_window_w [1][5];
    logic [15:0] i_rho_plus_box_wfh_col_w;
    logic [15:0] i_rho_plus_box_wfh_row_w;
    logic        i_rho_plus_box_wfh_valid_w;

    window_fetcher #(
        .DATA_WIDTH   (14),
        .IMAGE_WIDTH  (IMAGE_WIDTH),
        .IMAGE_HEIGHT (IMAGE_HEIGHT),
        .WINDOW_WIDTH (5),
        .WINDOW_HEIGHT(1),
        .BORDER_ENABLE(BORDER_ENABLE)
    ) i_rho_plus_box_window_fetcher_h (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .data_i (i_rho_plus_br_data_w),
        .col_i  (i_rho_plus_br_col_w),
        .row_i  (i_rho_plus_br_row_w),
        .valid_i(i_rho_plus_br_valid_w),

        .window_o(i_rho_plus_box_wfh_window_w),
        .col_o   (i_rho_plus_box_wfh_col_w),
        .row_o   (i_rho_plus_box_wfh_row_w),
        .valid_o (i_rho_plus_box_wfh_valid_w)
    );

    logic [17:0] i_rho_plus_box_bh_data_w;
    logic [15:0] i_rho_plus_box_bh_col_w;
    logic [15:0] i_rho_plus_box_bh_row_w;
    logic        i_rho_plus_box_bh_valid_w;

    custom_burt_h_sint14_to_sint18 i_rho_plus_burt_h (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .window_i(i_rho_plus_box_wfh_window_w),
        .col_i   (i_rho_plus_box_wfh_col_w),
        .row_i   (i_rho_plus_box_wfh_row_w),
        .valid_i (i_rho_plus_box_wfh_valid_w),

        .data_o (i_rho_plus_box_bh_data_w),
        .col_o  (i_rho_plus_box_bh_col_w),
        .row_o  (i_rho_plus_box_bh_row_w),
        .valid_o(i_rho_plus_box_bh_valid_w)
    );

    logic [11:0] i_rho_minus_box_data_w;
    logic [11:0] i_rho_minus_box_data_delay_w;
    logic [15:0] i_rho_minus_box_col_w;
    logic [15:0] i_rho_minus_box_row_w;
    logic        i_rho_minus_box_valid_w;

    custom_box_v_3_uint10_to_uint12 i_rho_minus_box_v (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .window_i(i_rho_minus_wfv_window_w),
        .col_i   (i_rho_minus_wfv_col_w),
        .row_i   (i_rho_minus_wfv_row_w),
        .valid_i (i_rho_minus_wfv_valid_w),

        .data_o (i_rho_minus_box_data_w),
        .col_o  (i_rho_minus_box_col_w),
        .row_o  (i_rho_minus_box_row_w),
        .valid_o(i_rho_minus_box_valid_w)
    );

    ////////////////////////////////////////////////////////////////
    // im_br = im - box(im)

    always@(posedge clk_i) begin
        i_rho_minus_box_data_delay_w <= i_rho_wfv_data_delay_w[7:0] * 4'b1001;
    end 

    logic [12:0] i_rho_minus_box_data_delay_zext_w;
    assign i_rho_minus_box_data_delay_zext_w = {1'b0, i_rho_minus_box_data_delay_w};

    logic [12:0] i_rho_minus_box_data_zext_w;
    assign i_rho_minus_box_data_zext_w = {1'b0, i_rho_minus_box_data_w};

    logic [13:0] i_rho_minus_br_data_w;
    logic [15:0] i_rho_minus_br_col_w;
    logic [15:0] i_rho_minus_br_row_w;
    logic        i_rho_minus_br_valid_w;

    always@(posedge clk_i) begin
        i_rho_minus_br_data_w  <= i_rho_minus_box_data_delay_zext_w - i_rho_minus_box_data_zext_w;
        i_rho_minus_br_col_w   <= i_rho_minus_box_col_w;
        i_rho_minus_br_row_w   <= i_rho_minus_box_row_w;
        i_rho_minus_br_valid_w <= i_rho_minus_box_valid_w;
    end

    logic [13:0] i_rho_minus_box_wfh_window_w [1][5];
    logic [15:0] i_rho_minus_box_wfh_col_w;
    logic [15:0] i_rho_minus_box_wfh_row_w;
    logic        i_rho_minus_box_wfh_valid_w;

    window_fetcher #(
        .DATA_WIDTH   (14),
        .IMAGE_WIDTH  (IMAGE_WIDTH),
        .IMAGE_HEIGHT (IMAGE_HEIGHT),
        .WINDOW_WIDTH (5),
        .WINDOW_HEIGHT(1),
        .BORDER_ENABLE(BORDER_ENABLE)
    ) i_rho_minus_box_window_fetcher_h (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .data_i (i_rho_minus_br_data_w),
        .col_i  (i_rho_minus_br_col_w),
        .row_i  (i_rho_minus_br_row_w),
        .valid_i(i_rho_minus_br_valid_w),

        .window_o(i_rho_minus_box_wfh_window_w),
        .col_o   (i_rho_minus_box_wfh_col_w),
        .row_o   (i_rho_minus_box_wfh_row_w),
        .valid_o (i_rho_minus_box_wfh_valid_w)
    );

    logic [17:0] i_rho_minus_box_bh_data_w;
    logic [15:0] i_rho_minus_box_bh_col_w;
    logic [15:0] i_rho_minus_box_bh_row_w;
    logic        i_rho_minus_box_bh_valid_w;

    custom_burt_h_sint14_to_sint18 i_rho_minus_box_burt_h (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .window_i(i_rho_minus_box_wfh_window_w),
        .col_i   (i_rho_minus_box_wfh_col_w),
        .row_i   (i_rho_minus_box_wfh_row_w),
        .valid_i (i_rho_minus_box_wfh_valid_w),

        .data_o (i_rho_minus_box_bh_data_w),
        .col_o  (i_rho_minus_box_bh_col_w),
        .row_o  (i_rho_minus_box_bh_row_w),
        .valid_o(i_rho_minus_box_bh_valid_w)
    );


    //--------------------------------------------
    // ------------- zip --------------
    logic [(18 * 2) - 1 : 0] i_rho_box_bh_data_w;
    logic [15:0]                       i_rho_box_bh_col_w;
    logic [15:0]                       i_rho_box_bh_row_w;
    logic                              i_rho_box_bh_valid_w;

    assign i_rho_box_bh_data_w  = {i_rho_plus_box_bh_data_w, i_rho_minus_box_bh_data_w};
    assign i_rho_box_bh_col_w   = i_rho_plus_box_bh_col_w;
    assign i_rho_box_bh_row_w   = i_rho_plus_box_bh_row_w;
    assign i_rho_box_bh_valid_w = i_rho_plus_box_bh_valid_w;

    logic [(18 * 2) - 1 : 0] i_rho_box_wfv_window_w [5][1];
    logic [15:0]                       i_rho_box_wfv_col_w;
    logic [15:0]                       i_rho_box_wfv_row_w;
    logic                              i_rho_box_wfv_valid_w;

    logic [18 - 1 : 0] i_rho_plus_box_wfv_window_w [5][1];
    logic [15:0]                 i_rho_plus_box_wfv_col_w;
    logic [15:0]                 i_rho_plus_box_wfv_row_w;
    logic                        i_rho_plus_box_wfv_valid_w;

    logic [18 - 1 : 0] i_rho_minus_box_wfv_window_w [5][1];
    logic [15:0]                 i_rho_minus_box_wfv_col_w;
    logic [15:0]                 i_rho_minus_box_wfv_row_w;
    logic                        i_rho_minus_box_wfv_valid_w;

    window_fetcher #(
        .DATA_WIDTH   (18 * 2),
        .IMAGE_WIDTH  (IMAGE_WIDTH),
        .IMAGE_HEIGHT (IMAGE_HEIGHT),
        .WINDOW_WIDTH (1),
        .WINDOW_HEIGHT(5),
        .BORDER_ENABLE(BORDER_ENABLE)
    ) i_rho_box_window_fetcher_v (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .data_i (i_rho_box_bh_data_w),
        .col_i  (i_rho_box_bh_col_w),
        .row_i  (i_rho_box_bh_row_w),
        .valid_i(i_rho_box_bh_valid_w),

        .window_o(i_rho_box_wfv_window_w),
        .col_o   (i_rho_box_wfv_col_w),
        .row_o   (i_rho_box_wfv_row_w),
        .valid_o (i_rho_box_wfv_valid_w)
    );

    // unzip
    always_comb begin
        for(int c = 0; c < 5; c++) begin
            i_rho_plus_box_wfv_window_w [c][0] = i_rho_box_wfv_window_w[c][0][(18 * 2) - 1: 18];
            i_rho_minus_box_wfv_window_w[c][0] = i_rho_box_wfv_window_w[c][0][18 - 1 : 0];
        end

        i_rho_plus_box_wfv_col_w   = i_rho_box_wfv_col_w;
        i_rho_plus_box_wfv_row_w   = i_rho_box_wfv_row_w;
        i_rho_plus_box_wfv_valid_w = i_rho_box_wfv_valid_w;

        i_rho_minus_box_wfv_col_w   = i_rho_box_wfv_col_w;
        i_rho_minus_box_wfv_row_w   = i_rho_box_wfv_row_w;
        i_rho_minus_box_wfv_valid_w = i_rho_box_wfv_valid_w;
    end


    logic [21:0] i_rho_plus_gaussian_data_uint_w;
    logic [15:0] i_rho_plus_gaussian_col_uint_w;
    logic [15:0] i_rho_plus_gaussian_row_uint_w;
    logic        i_rho_plus_gaussian_valid_uint_w;

    custom_burt_v_sint18_to_sint22 i_rho_plus_burt_v (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .window_i(i_rho_plus_box_wfv_window_w),
        .col_i   (i_rho_plus_box_wfv_col_w),
        .row_i   (i_rho_plus_box_wfv_row_w),
        .valid_i (i_rho_plus_box_wfv_valid_w),

        .data_o (i_rho_plus_gaussian_data_uint_w),
        .col_o  (i_rho_plus_gaussian_col_uint_w),
        .row_o  (i_rho_plus_gaussian_row_uint_w),
        .valid_o(i_rho_plus_gaussian_valid_uint_w)
    );

    logic [21:0] i_rho_minus_gaussian_data_uint_w;
    logic [15:0] i_rho_minus_gaussian_col_uint_w;
    logic [15:0] i_rho_minus_gaussian_row_uint_w;
    logic        i_rho_minus_gaussian_valid_uint_w;

    custom_burt_v_sint18_to_sint22 i_rho_minus_burt_v (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .window_i(i_rho_minus_box_wfv_window_w),
        .col_i   (i_rho_minus_box_wfv_col_w),
        .row_i   (i_rho_minus_box_wfv_row_w),
        .valid_i (i_rho_minus_box_wfv_valid_w),

        .data_o (i_rho_minus_gaussian_data_uint_w),
        .col_o  (i_rho_minus_gaussian_col_uint_w),
        .row_o  (i_rho_minus_gaussian_row_uint_w),
        .valid_o(i_rho_minus_gaussian_valid_uint_w)
    );

    ////////////////////////////////////////////////////////////////
    // converting S10.12 to FP16

    logic [FP_WIDTH_REG - 1 : 0] i_rho_plus_gaussian_data_w;
    logic [15:0]                 i_rho_plus_gaussian_col_w;
    logic [15:0]                 i_rho_plus_gaussian_row_w;
    logic                        i_rho_plus_gaussian_valid_w;

    logic [FP_WIDTH_REG - 1 : 0] i_rho_minus_gaussian_data_w;
    logic [15:0]                 i_rho_minus_gaussian_col_w;
    logic [15:0]                 i_rho_minus_gaussian_row_w;
    logic                        i_rho_minus_gaussian_valid_w;

    logic [15:0] col_delay;
    logic [15:0] row_delay;
    always@(posedge clk_i) begin
        col_delay <= i_rho_plus_gaussian_col_uint_w;
        row_delay <= i_rho_plus_gaussian_row_uint_w;
    end

    sint10_12_to_fp16_converter i_plus (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .sint10_12_i(i_rho_plus_gaussian_data_uint_w),
        .valid_i   (i_rho_plus_gaussian_valid_uint_w),

        .fp16_o (i_rho_plus_gaussian_data_w),
        .valid_o(i_rho_plus_gaussian_valid_w)
    );

    assign i_rho_plus_gaussian_col_w = col_delay;
    assign i_rho_plus_gaussian_row_w = row_delay;

    sint10_12_to_fp16_converter i_minus (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .sint10_12_i(i_rho_minus_gaussian_data_uint_w),
        .valid_i   (i_rho_minus_gaussian_valid_uint_w),

        .fp16_o (i_rho_minus_gaussian_data_w),
        .valid_o(i_rho_minus_gaussian_valid_w)
    );

    assign i_rho_minus_gaussian_col_w = col_delay;
    assign i_rho_minus_gaussian_row_w = row_delay;

    ////////////////////////////////////////////////////////////////
    // I_A calculation (and row col delay)
    logic [FP_WIDTH_REG - 1 : 0] i_a_plus_data_w;
    logic [15:0]                 i_a_plus_col_w;
    logic [15:0]                 i_a_plus_row_w;
    logic                        i_a_plus_valid_w;

    logic [FP_WIDTH_REG - 1 : 0] i_rho_plus_choice_w;
    logic [FP_WIDTH_REG - 1 : 0] i_rho_minus_choice_w;
    logic [15:0]                 i_rho_plus_col_choice_w;
    logic [15:0]                 i_rho_plus_row_choice_w;
    logic                        i_rho_plus_valid_choice_w;

    generate
        if(PREPROCESSING_ENABLE) begin
            assign i_rho_plus_choice_w       = i_rho_plus_gaussian_data_w;
            assign i_rho_minus_choice_w      = i_rho_minus_gaussian_data_w;
            assign i_rho_plus_col_choice_w   = i_rho_plus_gaussian_col_w;
            assign i_rho_plus_row_choice_w   = i_rho_plus_gaussian_row_w;
            assign i_rho_plus_valid_choice_w = i_rho_plus_gaussian_valid_w;
        end else begin
            assign i_rho_plus_choice_w       = i_rho_plus_direct_w;
            assign i_rho_minus_choice_w      = i_rho_minus_direct_w;
            assign i_rho_plus_col_choice_w   = col_direct_w;
            assign i_rho_plus_row_choice_w   = row_direct_w;
            assign i_rho_plus_valid_choice_w = valid_direct_w;
        end
    endgenerate

    floating_point_adder #(
        .EXP_WIDTH(EXP_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH)
    ) i_a_plus_adder (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .fp_a_i (i_rho_plus_choice_w),
        .fp_b_i (i_rho_minus_choice_w),
        .valid_i(i_rho_plus_valid_choice_w),

        .fp_o   (i_a_plus_data_w),
        .valid_o(i_a_plus_valid_w)
    );

    floating_point_adder_z #(
        .EXP_WIDTH(0),
        .FRAC_WIDTH(15)
    ) i_a_plus_col_delay (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .fp_a_i(i_rho_plus_col_choice_w),
        .fp_o  (i_a_plus_col_w)
    );

    floating_point_adder_z #(
        .EXP_WIDTH(0),
        .FRAC_WIDTH(15)
    ) i_a_plus_row_delay (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .fp_a_i(i_rho_plus_row_choice_w),
        .fp_o  (i_a_plus_row_w)
    );

    //----------------------------------------
    logic [FP_WIDTH_REG - 1 : 0] i_a_data_w;
    logic [15:0]                 i_a_col_w;
    logic [15:0]                 i_a_row_w;
    logic                        i_a_valid_w;

    floating_point_multiplier_exponent #(
        .EXP_WIDTH(EXP_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),
        .EXPONENT(-1)
    ) i_a_plus_multiplier (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .fp_a_i (i_a_plus_data_w),
        .valid_i(i_a_plus_valid_w),
        .fp_o   (i_a_data_w),
        .valid_o(i_a_valid_w)
    );

    floating_point_multiplier_z #(
        .EXP_WIDTH(0),
        .FRAC_WIDTH(15)
    ) i_a_col_delay (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .fp_a_i(i_a_plus_col_w),
        .fp_o  (i_a_col_w)
    );

    floating_point_multiplier_z #(
        .EXP_WIDTH(0),
        .FRAC_WIDTH(15)
    ) i_a_row_delay (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .fp_a_i(i_a_plus_row_w),
        .fp_o  (i_a_row_w)
    );

    ////////////////////////////////////////////////////////////////
    // I_T calculation
    logic [FP_WIDTH_REG - 1 : 0] i_t_minus_data_w;

    logic [FP_WIDTH_REG - 1 : 0] i_rho_minus_gaussian_data_negative_w;
    always_comb begin
        i_rho_minus_gaussian_data_negative_w[FP_WIDTH_REG - 1] = !i_rho_minus_choice_w[FP_WIDTH_REG - 1];
        i_rho_minus_gaussian_data_negative_w[FP_WIDTH_REG - 2 : 0] = i_rho_minus_choice_w[FP_WIDTH_REG - 2 : 0];
    end

    floating_point_adder #(
        .EXP_WIDTH(EXP_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH)
    ) i_t_minus_adder (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .fp_a_i (i_rho_plus_choice_w),
        .fp_b_i (i_rho_minus_gaussian_data_negative_w),
        .fp_o   (i_t_minus_data_w)
    );

    //----------------------------------------
    logic [FP_WIDTH_REG - 1 : 0] i_t_data_w;

    floating_point_multiplier_exponent #(
        .EXP_WIDTH(EXP_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),
        .EXPONENT(-1)
    ) i_t_minus_multiplier (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .fp_a_i (i_t_minus_data_w),
        .fp_o   (i_t_data_w)
    );
    
    assign i_a_o   = i_a_plus_data_w;
    assign i_t_o   = i_t_minus_data_w;
    assign col_o   = i_a_plus_col_w;
    assign row_o   = i_a_plus_row_w;
    assign valid_o = i_a_plus_valid_w;
    

endmodule
module dual_camera_wrapper #(
    parameter FP_M_IMAGE = 0,
    parameter FP_N_IMAGE = 0,
    parameter FP_S_IMAGE = 0,

    parameter RAW_IMAGE_HEIGHT = 0,
    parameter RAW_IMAGE_WIDTH  = 0,

    parameter IMAGE_HEIGHT = 0,
    parameter IMAGE_WIDTH  = 0,

    parameter N_LINES_POW2 = 0,
    parameter PIPE_ROW = 0,
    parameter PIPE_COL = 0,
    parameter PRECISION = 0
) (
    input clk_i,
    input rst_i,

    input       cameras_pclk_i      [2],
    input       cameras_hsync_i     [2],
    input       cameras_vsync_i     [2],
    input [7:0] cameras_d_i         [2],

    input [15:0] pre_bilinear_roi_i  [4],
    input [15:0] post_bilinear_roi_i [4],

    input [11+PRECISION-1:0] bilinear_matrices_i [2][3][3],

    // Output to stream buffer
    output       wr_clks_o      [2],
    output       wr_rsts_o      [2],
    output [7:0] wr_channels_o  [2],
    output       wr_valids_o    [2],
    output       wr_sof_o      
);
    // camera reader wiring 
    logic reader_async_fifo_rst_w [2];

    // output signals wiring
    logic       wr_clks_w      [2];
    logic       wr_rsts_w      [2];
    logic [7:0] wr_channels_w  [2];
    logic       wr_valids_w    [2];
    logic       wr_sof_w       [2];

    generate
        for(genvar gi = 0; gi < 2; gi++) begin
            ////////////////////////////////////////////////////////////////
            // camera reader --> first roi input
            pixel_data_interface #(
                .FP_M(FP_M_IMAGE), 
                .FP_N(FP_N_IMAGE), 
                .FP_S(FP_S_IMAGE)
            ) roi1_in (cameras_pclk_i[gi]);

            camera_reader reader (
                .reset_i(rst_i),

                .pixclk_i    (cameras_pclk_i [gi]), 
                .pixel_data_i(cameras_d_i    [gi]),
                .hsync_i     (cameras_hsync_i[gi]), 
                .vsync_i     (cameras_vsync_i[gi]),

                .pix_valid_o(roi1_in.valid), 
                .pix_o      (roi1_in.pixel),
                .row_o      (roi1_in.row), 
                .col_o      (roi1_in.col),

                .async_fifo_rst_o(reader_async_fifo_rst_w[gi])
            );
            defparam reader.ACTIVE_REGION_WIDTH  = RAW_IMAGE_WIDTH;
            defparam reader.ACTIVE_REGION_HEIGHT = RAW_IMAGE_HEIGHT;

            ////////////////////////////////////////////////////////////////
            // roi1 --> bilinear xform
            pixel_data_interface #(
                .FP_M(FP_M_IMAGE), 
                .FP_N(FP_N_IMAGE), 
                .FP_S(FP_S_IMAGE)
            ) bilinear_xform_in (cameras_pclk_i[gi]);

            roi pre_bilinear_roi (
                .in(roi1_in), 
                .out(bilinear_xform_in),
                .row_start_i(pre_bilinear_roi_i[0]), 
                .row_end_i  (pre_bilinear_roi_i[1] - 1),
                .col_start_i(pre_bilinear_roi_i[2]), 
                .col_end_i  (pre_bilinear_roi_i[3] - 1),

                .rst_n_i(!reader_async_fifo_rst_w[gi])
            );

            ////////////////////////////////////////////////////////////////
            // bilinear xform --> roi stage
            pixel_data_interface #(
                .FP_M(FP_M_IMAGE), 
                .FP_N(FP_N_IMAGE), 
                .FP_S(FP_S_IMAGE)
            ) roi2_in (cameras_pclk_i[gi]);
            
            if(gi == 1) begin
            bilinear_xform #(
                .WIDTH(IMAGE_WIDTH), 
                .HEIGHT(IMAGE_HEIGHT),
                .N_LINES_POW2(N_LINES_POW2),
                .PIPE_ROW(PIPE_ROW), 
                .PIPE_COL(PIPE_COL),
                .PRECISION(PRECISION),
                .CLKS_PER_PIXEL(1)
            ) bxform (
                .in(bilinear_xform_in), 
                .out(roi2_in),
                .matrix_i(bilinear_matrices_i[gi]), 
                .rst_n_i(!reader_async_fifo_rst_w[gi])
            );
            end else begin
             bilinear_xform #(
                .WIDTH(IMAGE_WIDTH), 
                .HEIGHT(IMAGE_HEIGHT),
                .N_LINES_POW2(N_LINES_POW2),
                .PIPE_ROW(PIPE_ROW), 
                .PIPE_COL(PIPE_COL),
                .PRECISION(PRECISION),
                .CLKS_PER_PIXEL(1)
            ) bxform (
                .in(bilinear_xform_in), 
                .out(roi2_in),
                .matrix_i(bilinear_matrices_i[gi]), 
                .rst_n_i(!reader_async_fifo_rst_w[gi])
            );
            end

            ////////////////////////////////////////////////////////////////
            // roi stage --> pixels out of camera read pipeline
            pixel_data_interface #(
                .FP_M(FP_M_IMAGE), 
                .FP_N(FP_N_IMAGE), 
                .FP_S(FP_S_IMAGE)
            ) pixels_out (cameras_pclk_i[gi]);

            roi post_bilinear_roi (
                .in(roi2_in), 
                .out(pixels_out),
                .row_start_i(post_bilinear_roi_i[0]), 
                .row_end_i  (post_bilinear_roi_i[1] - 1),
                .col_start_i(post_bilinear_roi_i[2]), 
                .col_end_i  (post_bilinear_roi_i[3] - 1),
                .rst_n_i(!reader_async_fifo_rst_w[gi])
            );
            
            assign wr_clks_w     [gi] = cameras_pclk_i         [gi];
            assign wr_rsts_w     [gi] = reader_async_fifo_rst_w[gi];
            assign wr_channels_w [gi] = pixels_out.pixel;      
            assign wr_valids_w   [gi] = pixels_out.valid;
            assign wr_sof_w      [gi] = (pixels_out.valid && 
                                     (pixels_out.row == 0) && 
                                     (pixels_out.col == 0));
        end
    endgenerate

    ////////////////////////////////////////////////////////////////
    // Output, only change is the sof bit is always determined by 
    // channel 0 (which is camera 0)
    assign wr_clks_o      = wr_clks_w;
    assign wr_rsts_o      = wr_rsts_w;
    assign wr_channels_o  = wr_channels_w;
    assign wr_valids_o    = wr_valids_w;
    assign wr_sof_o       = wr_sof_w[0];
endmodule
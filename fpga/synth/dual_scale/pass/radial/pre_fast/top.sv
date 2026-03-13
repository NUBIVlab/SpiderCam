`include "../../../../../rtl/pixel_data_interface.svh"
`include "../../../../../rtl/command_interface.svh"

module top #(
    // Raw image dims coming in from camera
    parameter RAW_IMAGE_WIDTH = 640,
    parameter RAW_IMAGE_HEIGHT = 480,

    // Cropped image going into bilinear xform
    parameter IMAGE_WIDTH = 512, 
    parameter IMAGE_HEIGHT = 480, 

    // Post-bilinear crop size.
    parameter ROI_WIDTH = 490,
    parameter ROI_HEIGHT = 450,

    // FP params image
    localparam FP_M_IMAGE = 8, //15
    localparam FP_N_IMAGE = 0, //16
    localparam FP_S_IMAGE = 0,  //1

    // High Frame Rate, output 1 window instead of 2
    // but at 4 times the frame rate.
    parameter FAST = 1,

    // i2c
    parameter string INIT_FILE_0 = FAST ? "../../synth/init_files/hm0360_initializer_program_fast_0.hex" :  "../../synth/init_files/hm0360_initializer_program_0.hex",
    parameter string INIT_FILE_1 = FAST ? "../../synth/init_files/hm0360_initializer_program_fast_1.hex" : "../../synth/init_files/hm0360_initializer_program_1.hex",
    parameter SCL_DIV = 50,

    // bilinear matrix parameters
    parameter PRECISION = 8,
    parameter N_LINES_POW2 = 6,
    parameter PIPE_ROW = 32,
    parameter PIPE_COL = 0,
    localparam CONSTANT = 0,

    // Input Stream Buffer 
    parameter CHANNELS_I     = 2,
    parameter DATA_WIDTH_I   = 8,
    parameter BUFFER_DEPTH_I = 32,

    // Output Stream Buffer
    parameter CHANNELS_O       = FAST ? 1 : 2,
    parameter DATA_WIDTH_O     = 8,
    parameter BUFFER_DEPTH_O   = 2**16,

    // Output Stream Deserializer
    parameter        DES_CHANNEL_DATA_WIDTH = DATA_WIDTH_O,
    parameter [63:0] MAGIC_NUM = 64'h42_49_56_46_52_41_4D_45,
                                  //  B  I  V  F  R  A  M  E 
    
    // don't touch these
    parameter NO_ZONES = 16,     
    parameter BORDER_ENABLE = 0, 

    // High Level DFDD algorithm settings
    parameter NO_SCALES            = 2,    
    parameter DX_DY_ENABLE         = 0,
    parameter RADIAL_ENABLE        = 1,
    parameter PREPROCESSING_ENABLE = 1
) (
    ////////////////////////////////
    // Dev board connections
    // FTDI pins
    //input ftdi_clk_12m,
    output logic sda_0_uart_tx,
    input scl_0_uart_rx,

    // LEDs and random GPIOs
    output logic [7:0] led,
    input btn,

    ////////////////////////////////
    // FT232H connections
    inout [7:0] ft245_async_d,
    input ft245_async_nrxf,
    input ft245_async_ntxe,
    output ft245_async_nrd,
    output ft245_async_nwr,

    ////////////////////////////////
    // Camera 0 interface
    // camera 0 pixel data
    input camera_0_pclk,
    input camera_0_hsync,
    input camera_0_vsync,
    input [7:0] camera_0_d,

    // camera 0 timing
    input camera_0_int,
    output logic camera_0_mclk,
    output logic camera_0_trig,

    // camera 0 i2c
    inout camera_0_sda,
    inout camera_0_scl,

    // camera 0 config
    output logic camera_0_xshut,
    output logic camera_0_clksel,
    output logic camera_0_xsleep,

    ////////////////////////////////
    // Camera 1 interface
    // camera 1 pixel data
    input camera_1_pclk,
    input camera_1_hsync,
    input camera_1_vsync,
    input [7:0] camera_1_d,

    // camera 1 timing
    input camera_1_int,
    output logic camera_1_mclk,
    output logic camera_1_trig,

    // camera 1 i2c
    inout camera_1_sda,
    inout camera_1_scl,

    // camera 1 config
    output logic camera_1_xshut,
    output logic camera_1_clksel,
    output logic camera_1_xsleep

    ////////////////////////////////
    // debug outputs
    //output logic [15:0] debug_o
);
    assign camera_0_xshut = 1'b1;
    assign camera_0_trig = 1'b0;

    assign camera_1_xshut = 1'b1;
    assign camera_1_trig = 1'b0;

    logic sys_reset;
    logic sys_reset_n;
    assign sys_reset_n = ~sys_reset;

    ////////////////////////////////////////////////////////////////
    // PLL
    // from an input clock of 12MHz, the PLL generates a 60MHz clock
    logic ftdi_clk_12m;
    OSCG OSCinst0 (.OSC(ftdi_clk_12m));
    defparam OSCinst0.DIV = 26;

    logic clk_pll;
    logic core_clk;
    logic ft232_clk;
    logic pll_locked;
    pll _pll (
        .clkin(ftdi_clk_12m), .clkout0(clk_pll), .locked(pll_locked)
    );

    ////////////////////////////////////////////////////////////////
    // Camera clocks and clock selector
    // Output 15MHz to camera mclk, select mclk for both cameras.
    // Combinational clock division bad practice, but ok for just 
    // outputting on clock pin only.
    logic [11:0] counter_60m;
    always_ff @(posedge clk_pll) begin
        counter_60m <= counter_60m + 1;
        if (sys_reset) counter_60m <= '0;
    end
    assign camera_0_clksel = 1'b1;
    always_comb camera_0_mclk = counter_60m[1];
    assign camera_1_clksel = 1'b1;
    always_comb camera_1_mclk = counter_60m[1];

    ////////////////////////////////////////////////////////////////
    // Core clock 
    // either select the 60 MHz pll generated clock or camera pclk
    assign core_clk = camera_0_pclk;
    assign ft232_clk = clk_pll;

    ////////////////////////////////////////////////////////////////
    // reset logic
    always_comb sys_reset = (!pll_locked || (btn == 1'b0));

    ////////////////////////////////////////////////////////////////
    // Camera wiring
    logic i2c_shutter_trig;
    wire cameras_xsleep [2] = {camera_0_xsleep, camera_1_xsleep};
    wire i2c_inits_done [2];
    wire cameras_sda    [2] = {camera_0_sda, camera_1_sda};
    wire cameras_scl    [2] = {camera_0_scl, camera_1_scl};
    wire cameras_pclk   [2] = {camera_0_pclk, camera_1_pclk};
    wire cameras_hsync  [2] = {camera_0_hsync, camera_1_hsync};
    wire cameras_vsync  [2] = {camera_0_vsync, camera_1_vsync};
    wire [7:0] cameras_d [2] = {camera_0_d, camera_1_d};

    ////////////////////////////////////////////////////////////////
    // i2c setup (controller + transmitter)
    // unforunately this has to be done here due to inout issues
    // even using the cameras_scl and cameras_sda will cause error,
    // must explicit refer to camera_0_scl..

    // i2c wiring (controller <-> transmitter)
    logic [15:0] i2c_init_addr_w         [2];
    logic [7:0]  i2c_init_data_w         [2];
    logic [1:0]  i2c_tx_phases_w         [2];
    logic        i2c_rw_bit_w            [2];
    logic        i2c_init_data_valid_w   [2];
    logic        i2c_transmitter_ready_w [2];

    generate
        for(genvar gi = 0; gi < 2; gi++) begin
            localparam INIT_FILE = gi == 0 ? INIT_FILE_0 : INIT_FILE_1;
            i2c_transmitter_controller #(
                .INIT_FILE(INIT_FILE)
            ) i2c_txctl (
                .clock(ftdi_clk_12m), 
                .reset(sys_reset),

                .reg_addr_o           (i2c_init_addr_w        [gi]), 
                .reg_data_o           (i2c_init_data_w        [gi]), 
                .data_valid_o         (i2c_init_data_valid_w  [gi]),
                .rw_bit_o             (i2c_rw_bit_w           [gi]), 
                .i2c_tx_phases_o      (i2c_tx_phases_w        [gi]),
                .i2c_transmitter_ready(i2c_transmitter_ready_w[gi]),

                .trigger_i({7'h0, i2c_shutter_trig}),
                .trigger_o({cameras_xsleep[gi], i2c_inits_done[gi]})
            );
            if(gi == 0) begin
                i2c_transmitter #(
                    .SCL_DIV(SCL_DIV)
                ) i2c_tx (
                    .clock(ftdi_clk_12m),
                    .reset(sys_reset),

                    .reg_addr    (i2c_init_addr_w        [gi]),
                    .reg_data    (i2c_init_data_w        [gi]),
                    .data_valid  (i2c_init_data_valid_w  [gi]),
                    .rw_bit      (i2c_rw_bit_w           [gi]),
                    .phase_enable(i2c_tx_phases_w        [gi]),
                    .ready       (i2c_transmitter_ready_w[gi]),
                    .sda_io      (camera_0_sda               ),
                    .scl_io      (camera_0_scl               )
                );
            end else begin
                i2c_transmitter #(
                    .SCL_DIV(SCL_DIV)
                ) i2c_tx (
                    .clock(ftdi_clk_12m),
                    .reset(sys_reset),

                    .reg_addr    (i2c_init_addr_w        [gi]),
                    .reg_data    (i2c_init_data_w        [gi]),
                    .data_valid  (i2c_init_data_valid_w  [gi]),
                    .rw_bit      (i2c_rw_bit_w           [gi]),
                    .phase_enable(i2c_tx_phases_w        [gi]),
                    .ready       (i2c_transmitter_ready_w[gi]),
                    .sda_io      (camera_1_sda               ),
                    .scl_io      (camera_1_scl               )
                );
            end
                
        end
    endgenerate

    ////////////////////////////////////////////////////////////////
    // ROI wiring
    // We have a single ROI that's shared between both camera 
    // pipelines. It comes after the bilinear transform. The ROIs 
    // should be in lockstep, which is why we put the ROI after.
    logic [15:0] pre_bilinear_roi [4];
    logic [15:0] post_bilinear_roi [4];

    ////////////////////////////////////////////////////////////////
    // bilinear transformation interfaces
    logic signed [11+PRECISION-1:0] bilinear_matrices [2][3][3];

    ////////////////////////////////////////////////////////////////
    // Dfdd constants wiring
    logic [15:0] a  [2][16];
    logic [15:0] b  [2][16];
    logic [17:0] r_squared [16];
    logic [15:0] w0 [2];
    logic [15:0] w1 [2];
    logic [15:0] w2 [2];
    logic [15:0] col_center;
    logic [15:0] row_center;
    logic [15:0] confidence [16];
    logic [15:0] depth      [16];
    logic [15:0] depth_min  [16];

    ////////////////////////////////////////////////////////////////
    // i2c shutter trig
    // Tells the i2c controllers when to release the cameras from reset.
    localparam SHUTTER_PERIOD = 6000000;
    logic [30:0] count;
    always_ff @(posedge ftdi_clk_12m) begin
        if (count >= SHUTTER_PERIOD) begin
            count <= 0;
            i2c_shutter_trig <= 1;
        end else begin
            count <= count + 1;
            i2c_shutter_trig <= 0;
        end
        if (sys_reset || !(i2c_inits_done[0] | i2c_inits_done[1])) begin
            count <= 0;
        end
    end
    assign sda_0_uart_tx = '1;

    ////////////////////////////////////////////////////////////////
    // Dual Camera Setup
    logic       wr_clks_dcw_sbi_w     [2];
    logic       wr_rsts_dcw_sbi_w     [2];
    logic [7:0] wr_channels_dcw_sbi_w [2];
    logic       wr_valids_dcw_sbi_w   [2];
    logic       wr_sof_dcw_sbi_w;

    dual_camera_wrapper #(
        .FP_M_IMAGE(FP_M_IMAGE),
        .FP_N_IMAGE(FP_N_IMAGE),
        .FP_S_IMAGE(FP_S_IMAGE),

        .RAW_IMAGE_HEIGHT(RAW_IMAGE_HEIGHT),
        .RAW_IMAGE_WIDTH(RAW_IMAGE_WIDTH),

        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .IMAGE_WIDTH(IMAGE_WIDTH),

        .N_LINES_POW2(N_LINES_POW2),
        .PIPE_ROW(PIPE_ROW),
        .PIPE_COL(PIPE_COL),
        .PRECISION(PRECISION)

    ) dual_camera_wrapper (
        .clk_i(ftdi_clk_12m),
        .rst_i(sys_reset),

        .cameras_pclk_i  (cameras_pclk),
        .cameras_hsync_i (cameras_hsync),
        .cameras_vsync_i (cameras_vsync),
        .cameras_d_i     (cameras_d),

        .pre_bilinear_roi_i(pre_bilinear_roi),
        .post_bilinear_roi_i(post_bilinear_roi),

        .bilinear_matrices_i(bilinear_matrices),

        .wr_clks_o    (wr_clks_dcw_sbi_w),
        .wr_rsts_o    (wr_rsts_dcw_sbi_w),
        .wr_channels_o(wr_channels_dcw_sbi_w),
        .wr_valids_o  (wr_valids_dcw_sbi_w),
        .wr_sof_o     (wr_sof_dcw_sbi_w)
    );


    ////////////////////////////////////////////////////////////////
    // Input Stream Buffer
    logic                    rd_stall_sbi_w;
    logic [DATA_WIDTH_I-1:0] rd_channels_sbi_w [CHANNELS_I];
    logic                    rd_valid_sbi_w;
    logic                    rd_sof_sbi_w;

    stream_buffer #(
        .CHANNELS(CHANNELS_I),
        .DATA_WIDTH(DATA_WIDTH_I),
        .BUFFER_DEPTH(BUFFER_DEPTH_I)
    ) stream_buffer_i (
        .wr_clks_i    (wr_clks_dcw_sbi_w),
        .wr_rsts_i    (wr_rsts_dcw_sbi_w),
        .wr_channels_i(wr_channels_dcw_sbi_w),
        .wr_valids_i  (wr_valids_dcw_sbi_w),
        .wr_sof_i     (wr_sof_dcw_sbi_w),

        .rd_clk_i     (core_clk),
        .rd_rst_i     (sys_reset),
        .rd_stall_i   (rd_stall_sbi_w),
        .rd_channels_o(rd_channels_sbi_w),
        .rd_valid_o   (rd_valid_sbi_w),
        .rd_sof_o     (rd_sof_sbi_w)
    );

    ////////////////////////////////////////////////////////////////
    // Processing Elements

    // uint8 to fp16 conversions and row/col tracking --------------
    assign rd_stall_sbi_w = 0;

    logic rd_sof_sbi_delay;
    always@(posedge core_clk) rd_sof_sbi_delay <= rd_sof_sbi_w;

    logic [7:0] uint8_in_0;
    logic [7:0] uint8_in_1;
    logic        valid_in_0;
    
    always@(posedge core_clk) begin
        uint8_in_0 <= rd_channels_sbi_w[0];
        uint8_in_1 <= rd_channels_sbi_w[1];

        if(sys_reset) begin
            valid_in_0 <= 0;
        end else begin
            valid_in_0 <= rd_valid_sbi_w;
        end
    end

    logic [15:0] col_in;
    logic [15:0] col_in_next;
    logic [15:0] row_in;
    logic [15:0] row_in_next;
    logic [15:0] col_in_0;
    logic [15:0] row_in_0;

    always_ff@(posedge core_clk) begin
        if(sys_reset) begin
            col_in <= 0;
            row_in <= 0;
        end else begin
            col_in <= col_in_next;
            row_in <= row_in_next;
        end
    end

    always_comb begin
        col_in_next = col_in;
        row_in_next = row_in;

        if(valid_in_0) begin
            col_in_next = col_in + 1;
            if(col_in == (ROI_WIDTH - 1)) begin
                col_in_next = 0;
                row_in_next = row_in + 1;
                if(row_in == (ROI_HEIGHT - 1)) begin
                    row_in_next = 0;
                end
            end
        end
        
        if(rd_sof_sbi_delay && valid_in_0) begin
            col_in_next = 1;
            row_in_next = 0;
        end
    end

    assign col_in_0 = rd_sof_sbi_delay && valid_in_0 ? 0 : col_in;
    assign row_in_0 = rd_sof_sbi_delay && valid_in_0 ? 0 : row_in;

    // main processing elements ----------------------------
    logic [15:0] fp16_z_out;
    logic [15:0] fp16_c_out;
    logic [15:0] col_out;
    logic [15:0] row_out;
    logic        valid_out;

    logic [15:0] w_dual [2][3];

    // this can be hardcoded to just 1
    assign w_dual = '{'{w0[0], w1[0], w2[0]},
                      '{w0[1], w1[1], w2[1]}};
    
    dual_scale_wrapper_fp16 #(
        .IMAGE_WIDTH(ROI_WIDTH),
        .IMAGE_HEIGHT(ROI_HEIGHT),
        .DX_DY_ENABLE(DX_DY_ENABLE),
        .BORDER_ENABLE(BORDER_ENABLE),
        .NO_ZONES(NO_ZONES),
        .NO_SCALES(NO_SCALES),
        .RADIAL_ENABLE(RADIAL_ENABLE),
        .PREPROCESSING_ENABLE(PREPROCESSING_ENABLE)
    ) dual_scale (
        .clk_i(core_clk),
        .rst_i(sys_reset),

        .i_rho_plus_uint8_i (uint8_in_0),
        .i_rho_minus_uint8_i(uint8_in_1),
        .col_i        (col_in_0),
        .row_i        (row_in_0),
        .valid_i      (valid_in_0),

        .w_i  (w_dual),
        .a_i  (a),
        .b_i  (b),
        .r_squared_i(r_squared),
        .confidence_i(confidence),
        .depth_i(depth),
        .depth_min_i(depth_min),
        .col_center_i(col_center),
        .row_center_i(row_center),

        .z_o    (fp16_z_out),
        .c_o    (fp16_c_out),
        .col_o  (col_out),
        .row_o  (row_out),
        .valid_o(valid_out)
    );

    // fp16 to u8 conversions -------------------------------
    logic [15:0] col_delay;
    logic [15:0] row_delay;

    always@(posedge core_clk) begin
        col_delay <= col_out;
        row_delay <= row_out;  
    end

    logic                    wr_clks_sbo_w     [CHANNELS_O];
    logic                    wr_rsts_sbo_w     [CHANNELS_O];
    logic [DATA_WIDTH_O-1:0] wr_channels_sbo_w [CHANNELS_O];
    logic                    wr_valids_sbo_w   [CHANNELS_O];
    logic                    wr_sof_sbo_w;

    logic wr_sof_sbo_delay;
    generate
        if(FAST) begin
            assign wr_sof_sbo_delay = ((col_delay == 0) && (row_delay == 0));
            assign wr_sof_sbo_w     = wr_sof_sbo_delay;
        end else begin
            assign wr_sof_sbo_w = rd_sof_sbi_w;
        end
    endgenerate

    generate 
        if(FAST) begin
            assign wr_clks_sbo_w = '{core_clk};
            assign wr_rsts_sbo_w = '{sys_reset};

            fp16_u8_converter #(
                .LEAD_EXPONENT_UNBIASED(0)
            ) z_fp16_u8_converter (
                .clk_i(core_clk),
                .rst_i(sys_reset),

                .fp16_i(fp16_z_out),
                .valid_i(valid_out),

                .u8_o(wr_channels_sbo_w[0]),
                .valid_o(wr_valids_sbo_w[0])
            );

        end else begin
            assign wr_clks_sbo_w = '{core_clk, core_clk};
            assign wr_rsts_sbo_w = '{sys_reset, sys_reset};

            assign wr_channels_sbo_w[0] = rd_channels_sbi_w[0];

            assign wr_valids_sbo_w[0] = rd_valid_sbi_w;

            fp16_u8_converter #(
                .LEAD_EXPONENT_UNBIASED(0)
            ) z_fp16_u8_converter (
                .clk_i(core_clk),
                .rst_i(sys_reset),

                .fp16_i(fp16_z_out),
                .valid_i(valid_out),

                .u8_o(wr_channels_sbo_w[1]),
                .valid_o(wr_valids_sbo_w[1])
            );
        end
    endgenerate

    ////////////////////////////////////////////////////////////////
    // Output Stream Buffer
    logic                    rd_stall_sbo_sbd_w;
    logic [DATA_WIDTH_O-1:0] rd_channels_sbo_sbd_w [CHANNELS_O];
    logic                    rd_valid_sbo_sbd_w;
    logic                    rd_sof_sbo_sbd_w;

    stream_buffer #(
        .CHANNELS(CHANNELS_O),
        .DATA_WIDTH(DATA_WIDTH_O),
        .BUFFER_DEPTH(BUFFER_DEPTH_O)
    ) stream_buffer_o (
        .wr_clks_i    (wr_clks_sbo_w),
        .wr_rsts_i    (wr_rsts_sbo_w),
        .wr_channels_i(wr_channels_sbo_w),
        .wr_valids_i  (wr_valids_sbo_w),
        .wr_sof_i     (wr_sof_sbo_w),

        .rd_clk_i     (ft232_clk),
        .rd_rst_i     (sys_reset),
        .rd_stall_i   (rd_stall_sbo_sbd_w),
        .rd_channels_o(rd_channels_sbo_sbd_w),
        .rd_valid_o   (rd_valid_sbo_sbd_w),
        .rd_sof_o     (rd_sof_sbo_sbd_w)
    );

    ////////////////////////////////////////////////////////////////
    // Output Stream Buffer Deserializer
    // since this is just camera previewer, we can directly deserialize
    logic [15:0] ft232_fifo_space_left;
    logic ft232_fifo_has_space;
    always_ff @(posedge ft232_clk) ft232_fifo_has_space <= (ft232_fifo_space_left > 32);

    logic [7:0] ft245_fifo_write_data;
    logic ft245_fifo_write_data_valid;

    stream_channel_deserializer #(
        .CHANNELS(CHANNELS_O),
        .DATA_WIDTH(DATA_WIDTH_O),
        .WIDTH(ROI_WIDTH),
        .HEIGHT(ROI_HEIGHT),
        .DES_CHANNEL_DATA_WIDTH(DES_CHANNEL_DATA_WIDTH),
        .MAGIC_NUM(MAGIC_NUM)
    ) stream_channel_deserializer (
        .rd_clk_i     (ft232_clk),
        .rd_rst_i     (sys_reset),

        .rd_stall_o   (rd_stall_sbo_sbd_w),
        .rd_channels_i(rd_channels_sbo_sbd_w),
        .rd_valid_i   (rd_valid_sbo_sbd_w),
        .rd_sof_i     (rd_sof_sbo_sbd_w),

        .wr_stall_i  (!ft232_fifo_has_space),
        .wr_channel_o(ft245_fifo_write_data),
        .wr_valid_o  (ft245_fifo_write_data_valid)
    );

    ////////////////////////////////////////////////////////////////
    // ft232 output
    logic [7:0] ft232h_ext_data;
    logic       ft232h_ext_valid;
    ft232h_async_driver dut (
        .clk_in(ft232_clk), 
        .reset_in(sys_reset),
        .fifo_data_in(ft245_fifo_write_data), 
        .fifo_data_valid_in(ft245_fifo_write_data_valid),
        .remaining_space_out(ft232_fifo_space_left),
        .fifo_data_out(ft232h_ext_data), 
        .fifo_data_valid_out(ft232h_ext_valid),
        .ft245_async_d_inout(ft245_async_d),
        .ft245_async_nrxf_in(ft245_async_nrxf), 
        .ft245_async_ntxe_in(ft245_async_ntxe),
        .ft245_async_nrd_out(ft245_async_nrd), 
        .ft245_async_nwr_out(ft245_async_nwr)
    );
    defparam dut.TX_STATE_TICKS = 4;

    ////////////////////////////////////////////////////////////////
    // Small ft232h input deserializer
    logic [47:0] ft232h_ext_des_data;
    logic        ft232h_ext_des_valid;
    word_concatenator #(
        .INPUT_WIDTH(8),
        .NUM_WORDS_TO_CONCAT(6)
    ) wc (
        .clk_i(ft232_clk),
        .reset_i(sys_reset),
        .data_i(ft232h_ext_data),
        .data_valid_i(ft232h_ext_valid),

        .accumulated_data_o(ft232h_ext_des_data),
        .accumulated_data_valid_o(ft232h_ext_des_valid)
    );

    ////////////////////////////////////////////////////////////////
    // Controller for Constants
    command_interface #(
        .ADDR_WIDTH(16),
        .DATA_WIDTH(32)
    ) command_in (ft232_clk);

    assign command_in.addr = ft232h_ext_des_data[47:32];
    assign command_in.data = ft232h_ext_des_data[31:0];
    assign command_in.valid = ft232h_ext_des_valid;

    controller #(
        .PRECISION(PRECISION)
    ) constants_controller (
        .rst_n_i(sys_reset_n),
        .in(command_in),
        .a_o(a),
        .b_o(b),
        .r_squared_o(r_squared),
        .w0_o(w0),
        .w1_o(w1),
        .w2_o(w2),
        .col_center_o(col_center),
        .row_center_o(row_center),
        .confidence_o(confidence),
        .depth_o(depth),
        .depth_min_o(depth_min),
        .bilinear_matrices_o(bilinear_matrices),
        .pre_bilinear_roi_boundaries_o(pre_bilinear_roi),
        .post_bilinear_roi_boundaries_o(post_bilinear_roi)
    );

    defparam constants_controller.PRE_XFORM_ROI_DIMS = '{IMAGE_HEIGHT, IMAGE_WIDTH};
    defparam constants_controller.POST_XFORM_ROI_DIMS = '{ROI_HEIGHT, ROI_WIDTH};
    defparam constants_controller.DEFAULT_PRE_XFORM_ROI_CORNER = '{0, (RAW_IMAGE_WIDTH - IMAGE_WIDTH) / 2};
    defparam constants_controller.DEFAULT_POST_XFORM_ROI_CORNER = '{0, (IMAGE_WIDTH - ROI_WIDTH) / 2};

    ////////////////////////////////////////////////////////////////
    // debug outputs going to logic analyzer
    always_comb begin
        //debug_o = '1;
        /*
        debug_o[0] = dual_camera_wrapper.pixels_out.valid;
        debug_o[1] = dual_camera_wrapper.sof;
        debug_o[2] = fifos_definitely_not_empty;
        debug_o[3] = ft232_fifo_has_space;
        debug_o[4] = output_valid;
        */
    end

    ////////////////////////////////////////////////////////////////
    // LEDs
    always_comb begin
        //led[6:0] = bilinear_matrices[0][0][0];
        /*
        led[7] = !pll_locked;

        led[0] = !sys_reset;
        led[1] = !rd_valid_sbi_sbd_w;
        led[2] = !rd_stall_sbi_sbd_w;
        
        led[3] = !ft245_fifo_write_data_valid;
        led[4] = !ft232_fifo_has_space;
        */
    end
endmodule

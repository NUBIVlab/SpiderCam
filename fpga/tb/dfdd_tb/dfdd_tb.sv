////////////////////////////////////////////////////////////////
// interface include 
`include "dfdd_inf.svh"

////////////////////////////////////////////////////////////////
// package includes
`include "utilities_pkg.svh"
`include "drivers_pkg.svh"
`include "generators_pkg.svh"
`include "golden_models_pkg.svh"
`include "monitors_pkg.svh"
`include "scoreboards_pkg.svh"

////////////////////////////////////////////////////////////////
// imports
import utilities_pkg::*;
import drivers_pkg::*;
import generators_pkg::*;
import golden_models_pkg::*;
import monitors_pkg::*;
import scoreboards_pkg::*;

////////////////////////////////////////////////////////////////
// RTL includes
// third party
`include "async_fifo.v"
// main
`include "convolution_floating_point_z.sv"
`include "convolution_floating_point.sv"
`include "floating_point_adder_z.sv"
`include "floating_point_adder.sv"
`include "floating_point_divider_z.sv"
`include "floating_point_divider.sv"
`include "floating_point_multiplier_exponent.sv"
`include "floating_point_multiplier_z.sv"
`include "floating_point_multiplier.sv"
`include "stream_buffer.sv"
`include "stream_deserializer.sv"
`include "uint8_fp16_converter.sv"
`include "window_fetcher_z.sv"
`include "window_fetcher.sv"
`include "zero_latency_buffer.sv"
// project/dfdd
`include "box_h_0_fp16.sv"
`include "box_v_0_fp16.sv"
`include "burt_h_0_fp16.sv"
`include "burt_v_0_fp16.sv"
`include "burt_h_1_fp16.sv"
`include "burt_v_1_fp16.sv"
`include "downsampler_0_fp16.sv"
`include "downsampler_h_0_fp16.sv"
`include "downsampler_v_0_fp16.sv"
`include "downsampler_h_1_fp16.sv"
`include "downsampler_v_1_fp16.sv"
`include "dual_scale_adder_fp16.sv"
`include "dx_0_fp16.sv"
`include "dy_0_fp16.sv"
`include "pass_0_fp16.sv"
`include "dx_1_fp16.sv"
`include "dy_1_fp16.sv"
`include "pass_1_fp16.sv"
`include "first_scale_fp16.sv"
`include "pass_dx_dy_adder_fp16.sv"
`include "preprocessor_fp16.sv"
`include "upsampler_0_fp16.sv"
`include "upsampler_h_0_fp16.sv"
`include "upsampler_h_1_fp16.sv"
`include "upsampler_v_0_fp16.sv"
`include "upsampler_v_1_fp16.sv"
`include "v_w_adder_1_fp16.sv"
`include "v_w_divider_0.sv"
`include "zero_inserter.sv"
`include "zero_scale_fp16.sv"
`include "dual_scale_wrapper_fp16.sv"
`include "upsampler_sh_h_0_fp16.sv"
`include "upsampler_sh_v_0_fp16.sv"
`include "upsampler_sh_h_1_fp16.sv"
`include "upsampler_sh_v_1_fp16.sv"
`include "uint8_12_to_fp16_converter.sv"
`include "custom_box_h_3_uint8_to_uint10.sv"
`include "custom_box_v_3_uint10_to_uint12.sv"
`include "custom_burt_h_uint12_to_uint16.sv"
`include "custom_burt_v_uint16_to_uint20.sv"
`include "preprocessor_hybrid_uint8_to_fp16.sv"
`include "custom_burt_h_sint14_to_sint18.sv"
`include "custom_burt_v_sint18_to_sint22.sv"
`include "sint10_12_to_fp16_converter.sv"
`include "box_h_0_ones_fp16.sv"
`include "box_v_0_ones_fp16.sv"
`include "box_h_0_ones_9x9_fp16.sv"
`include "box_v_0_ones_9x9_fp16.sv"
`include "box_h_0_ones_11_fp16.sv"
`include "box_v_0_ones_11_fp16.sv"
`include "radial_a_b_fp16.sv"
`include "radial_c_z_fp16.sv"

////////////////////////////////////////////////////////////////
// timescale 

module dfdd_tb();

    ////////////////////////////////////////////////////////////////
    // localparams
    localparam IMAGE_WIDTH  = 512;
    localparam IMAGE_HEIGHT = 400;

    localparam EXP_WIDTH = 5;
    localparam FRAC_WIDTH = 10;
    localparam FP_WIDTH_REG = 1 + FRAC_WIDTH + EXP_WIDTH;

    localparam SCALES = 2;

    localparam BORDER_EXTENSION_CONSTANT = 0;
    localparam BORDER_ENABLE             = 0;
    
    localparam real CLK_PERIOD = 10;

    localparam type T_image = Image #(
        .DATA_WIDTH(FP_WIDTH_REG),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT)
    );

    localparam type I = virtual dfdd_inf #(
        .EXP_WIDTH(EXP_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),
        .SCALES(2)
    );

    ////////////////////////////////////////////////////////////////
    // clock generation and reset
    logic clk = 0;
    logic rst = 0;
    always begin #(CLK_PERIOD/2); clk = ~clk; end

    ////////////////////////////////////////////////////////////////
    // interface
    dfdd_inf #(
        .EXP_WIDTH(EXP_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),
        .SCALES(2)
    ) bfm (.clk_i(clk), .rst_i(rst));
    
    ////////////////////////////////////////////////////////////////
    // DUT
    logic [15:0] w [2][3];
    logic [15:0] w_t;
    logic [15:0] a [2][16];
    logic [15:0] b [2][16];
    logic [17:0] r_squared[16];
    logic [15:0] c [16];
    logic [15:0] z [16];
    logic [15:0] col_center;
    logic [15:0] row_center;


    assign w = '{'{16'h2c0b,16'h2e38,16'h2fdd},
                 '{16'h33d4,16'h3385,16'h3398}};
    assign a = '{{16'h3c79,16'h3c79,16'h3c79,16'h3c79,16'h3c79,16'h3c79,16'h3c79,16'h3c79,16'h3c79,16'h3c79,16'h3c79,16'h3c79,16'h3c79,16'h3c79,16'h3c79,16'h3c79},
                 {16'h3ea0,16'h3ea0,16'h3ea0,16'h3ea0,16'h3ea0,16'h3ea0,16'h3ea0,16'h3ea0,16'h3ea0,16'h3ea0,16'h3ea0,16'h3ea0,16'h3ea0,16'h3ea0,16'h3ea0,16'h3ea0}};
    assign b = '{{16'h4562,16'h4562,16'h4562,16'h4562,16'h4562,16'h4562,16'h4562,16'h4562,16'h4562,16'h4562,16'h4562,16'h4562,16'h4562,16'h4562,16'h4562,16'h4562},
                 {16'h410b,16'h410b,16'h410b,16'h410b,16'h410b,16'h410b,16'h410b,16'h410b,16'h410b,16'h410b,16'h410b,16'h410b,16'h410b,16'h410b,16'h410b,16'h410b}};
    assign r_squared = {default : 16'h0000};
    assign c = '{default : 16'h0000};
    assign z = '{default : 16'h7fff};
    assign col_center = 25;
    assign row_center = 25;

    //assign w = '{'{16'h3c00,16'h3c00,16'h3c00},
    //             '{16'h3c00,16'h3c00,16'h3c00}};

    //assign b = '{16'h2f52,16'h3694};
    //assign a = '{16'h3eac, 16'h3b95};

    //assign a = '{16'h3c00,16'h3c00};
    //assign b = '{16'h3c00, 16'h3c00};

    
    


    //assign a = '{16'h3c7c,16'h3e09};
    //assign b = '{16'h454d, 16'h4129};

    logic [15:0] fp16_in_0;
    logic [15:0] fp16_in_1;
    logic [15:0] col_in;
    logic [15:0] row_in;
    logic        valid_in;

    always@(posedge clk) begin
        col_in <= bfm.col_i;
        row_in <= bfm.row_i;
    end

    /*
    uint8_fp16_converter img_0_uint8_fp16_converter (
        .clk_i(clk),
        .rst_i(rst),
        .uint8_i(bfm.i_rho_plus_uint8_i),
        .valid_i(bfm.valid_i),
        .fp16_o (bfm.i_rho_plus_i),
        .valid_o(valid_in)
    );

    uint8_fp16_converter img_1_uint8_fp16_converter (
        .clk_i(clk),
        .rst_i(rst),
        .uint8_i(bfm.i_rho_minus_uint8_i),
        .fp16_o (bfm.i_rho_minus_i)
    );
    */

    dual_scale_wrapper_fp16 #(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .DX_DY_ENABLE(1),
        .BORDER_ENABLE(0),
        .NO_ZONES(16),
        .NO_SCALES(2),
        .RADIAL_ENABLE(1),
        .PREPROCESSING_ENABLE(1)
    ) dual_scale (
        .clk_i(clk),
        .rst_i(rst),

        .i_rho_plus_uint8_i (bfm.i_rho_plus_uint8_i),
        .i_rho_minus_uint8_i(bfm.i_rho_minus_uint8_i),
        .col_i        (bfm.col_i),
        .row_i        (bfm.row_i),
        .valid_i      (bfm.valid_i),

        .w_i  (w),
        .w_t_i(w_t),
        .a_i  (a),
        .b_i  (b),
        .r_squared_i(r_squared),
        .confidence_i(c),
        .depth_i(z),
        .col_center_i(col_center),
        .row_center_i(row_center),

        .z_o    (bfm.z_o),
        .c_o    (bfm.c_o),
        .col_o  (bfm.col_o),
        .row_o  (bfm.row_o),
        .valid_o(bfm.valid_o)
    );
    
    // dual_scale_wrapper.sv here

    initial begin
        ////////////////////////////////////////////////////////////////
        // generator
        static TriggerableQueueBroadcaster #(T_image) generator_out_broadcast_0 = new();
        static TriggerableQueueBroadcaster #(T_image) generator_out_broadcast_1 = new();
        static DualImageGenerator #(T_image, T_image) generator = new(generator_out_broadcast_0, generator_out_broadcast_1);

        ////////////////////////////////////////////////////////////////
        // driver
        static TriggerableQueue #(T_image) driver_in_queue_0 = new();
        static TriggerableQueue #(T_image) driver_in_queue_1 = new();
        static DualImageDriver #(T_image, T_image, I) driver = new(driver_in_queue_0, driver_in_queue_1, bfm);

        ////////////////////////////////////////////////////////////////
        // monitor
        static TriggerableQueueBroadcaster #(T_image) monitor_out_broadcast_0 = new();
        static TriggerableQueueBroadcaster #(T_image) monitor_out_broadcast_1 = new();
        static DualImageMonitor #(T_image, T_image, I) monitor = new(monitor_out_broadcast_0, monitor_out_broadcast_1, bfm);

        ////////////////////////////////////////////////////////////////
        // Queue Linkage
        generator_out_broadcast_0.add_queue(driver_in_queue_0);
        generator_out_broadcast_1.add_queue(driver_in_queue_1);

        ////////////////////////////////////////////////////////////////
        // Set up dump 
        //$dumpfile("waves.vcd");
        //$dumpvars(0, dfdd_tb);

        ////////////////////////////////////////////////////////////////
        // Reset logic
        bfm.valid_i <= 0;
        rst <= 0;
        repeat(5) @(posedge clk)
        rst <= 1;
        repeat(7) @(posedge clk)
        rst <= 0;
        // Run
        fork
            generator.run();
            driver.run();
            monitor.run();
            //watchdog.run();
        join_none

        #4000000000;
        $finish;
    end



endmodule
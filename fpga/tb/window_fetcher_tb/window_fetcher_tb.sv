////////////////////////////////////////////////////////////////
// interface include 
`include "window_fetcher_inf.svh"

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
`include "async_fifo.v"
`include "window_fetcher.sv"

////////////////////////////////////////////////////////////////
// timescale 

module window_fetcher_tb();

    ////////////////////////////////////////////////////////////////
    // localparams
    localparam DATA_WIDTH   = 8;
    localparam IMAGE_WIDTH  = 5;
    localparam IMAGE_HEIGHT = 5;

    localparam WINDOW_WIDTH  = 1;
    localparam WINDOW_HEIGHT = 5;
    localparam WINDOW_WIDTH_CENTER_OFFSET  = 0;
    localparam WINDOW_HEIGHT_CENTER_OFFSET = 0;

    localparam BORDER_EXTENSION_CONSTANT = 0;
    localparam BORDER_ENABLE             = 1;
    
    localparam real CLK_PERIOD = 10;

    localparam type T_image = Image #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT)
    );

    localparam type T_window = Image #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMAGE_WIDTH(WINDOW_WIDTH),
        .IMAGE_HEIGHT(WINDOW_HEIGHT)
    );

    localparam type I = virtual window_fetcher_inf #(
        .DATA_WIDTH(DATA_WIDTH),
        .WINDOW_WIDTH(WINDOW_WIDTH),
        .WINDOW_HEIGHT(WINDOW_HEIGHT)
    );

    ////////////////////////////////////////////////////////////////
    // clock generation and reset
    logic clk = 0;
    logic rst = 0;
    always begin #(CLK_PERIOD/2); clk = ~clk; end

    ////////////////////////////////////////////////////////////////
    // interface
    window_fetcher_inf #(
        .DATA_WIDTH(DATA_WIDTH),
        .WINDOW_WIDTH(WINDOW_WIDTH),
        .WINDOW_HEIGHT(WINDOW_HEIGHT)
    ) bfm (.clk_i(clk), .rst_i(rst));
    
    ////////////////////////////////////////////////////////////////
    // DUT
    window_fetcher #(
        .DATA_WIDTH(DATA_WIDTH),

        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),

        .WINDOW_WIDTH(WINDOW_WIDTH),
        .WINDOW_HEIGHT(WINDOW_HEIGHT),
        .WINDOW_WIDTH_CENTER_OFFSET(WINDOW_WIDTH_CENTER_OFFSET),
        .WINDOW_HEIGHT_CENTER_OFFSET(WINDOW_HEIGHT_CENTER_OFFSET),

        .BORDER_EXTENSION_CONSTANT(BORDER_EXTENSION_CONSTANT),
        .BORDER_ENABLE(BORDER_ENABLE)
    ) dut (
        .clk_i(clk),
        .rst_i(rst),

        .data_i(bfm.data_i),
        .col_i(bfm.col_i),
        .row_i(bfm.row_i),
        .valid_i(bfm.valid_i),

        .window_o(bfm.window_o),
        .col_o(bfm.col_o),
        .row_o(bfm.row_o),
        .valid_o(bfm.valid_o)
    );

    initial begin
        ////////////////////////////////////////////////////////////////
        // generator
        static TriggerableQueueBroadcaster #(T_image) generator_out_broadcast = new();
        static ImageGenerator #(T_image) generator = new(generator_out_broadcast);

        ////////////////////////////////////////////////////////////////
        // driver
        static TriggerableQueue #(T_image) driver_in_queue = new();
        static WindowFetcherDriver #(T_image, I) driver = new(driver_in_queue, bfm);

        ////////////////////////////////////////////////////////////////
        // golden model
        static TriggerableQueue #(T_image) golden_in_queue = new();
        static TriggerableQueueBroadcaster #(T_window) golden_out_broadcast = new();
        static WindowFetcherModel #(
            T_image, T_window, BORDER_ENABLE, BORDER_EXTENSION_CONSTANT
        ) golden = new(golden_in_queue, golden_out_broadcast);

        ////////////////////////////////////////////////////////////////
        // monitor
        static TriggerableQueueBroadcaster #(T_window) monitor_out_broadcast = new();
        static WindowFetcherMonitor #(T_window, I) monitor = new(monitor_out_broadcast, bfm);


        ////////////////////////////////////////////////////////////////
        // scoreboard
        static TriggerableQueue #(T_window) scoreboard_in_queue_dut = new();
        static TriggerableQueue #(T_window) scoreboard_in_queue_golden = new();
        static WindowFetcherScoreboard #(
            T_window, BORDER_ENABLE, BORDER_EXTENSION_CONSTANT
        ) scoreboard = new(scoreboard_in_queue_dut, scoreboard_in_queue_golden);

        ////////////////////////////////////////////////////////////////
        // watch dog

        ////////////////////////////////////////////////////////////////
        // Queue Linkage
        generator_out_broadcast.add_queue(driver_in_queue);
        generator_out_broadcast.add_queue(golden_in_queue);
        monitor_out_broadcast.add_queue(scoreboard_in_queue_dut);
        golden_out_broadcast.add_queue(scoreboard_in_queue_golden);

        ////////////////////////////////////////////////////////////////
        // Set up dump 
        $dumpfile("waves.vcd");
        $dumpvars(0, window_fetcher_tb);

        ////////////////////////////////////////////////////////////////
        // Additional runtime time setup
        generator.col_center = ((WINDOW_WIDTH - 1) / 2) + WINDOW_WIDTH_CENTER_OFFSET;
        generator.row_center = ((WINDOW_HEIGHT - 1) / 2) + WINDOW_HEIGHT_CENTER_OFFSET;

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
            golden.run();
            monitor.run();
            scoreboard.run();
            //watchdog.run();
        join_none

        #4000000000;
        $finish;
    end



endmodule
////////////////////////////////////////////////////////////////
// interface include 
`include "floating_point_inf.svh"

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
`include "floating_point_multiplier.sv"

////////////////////////////////////////////////////////////////
// timescale 

module floating_point_multiplier_32_tb();

    ////////////////////////////////////////////////////////////////
    // localparams
    localparam EXP_WIDTH = 8;
    localparam FRAC_WIDTH = 23;
    
    localparam real CLK_PERIOD = 10;

    localparam type T = FloatingPoint #(
        .EXP_WIDTH(EXP_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH)
    );

    localparam type I = virtual floating_point_inf #(
        .EXP_WIDTH(EXP_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH)
    );

    ////////////////////////////////////////////////////////////////
    // clock generation and reset
    logic clk = 0;
    logic rst = 0;
    always begin #(CLK_PERIOD/2); clk = ~clk; end

    ////////////////////////////////////////////////////////////////
    // interface
    floating_point_inf #(
        .EXP_WIDTH(EXP_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH)
    ) bfm (.clk_i(clk), .rst_i(rst));
    
    ////////////////////////////////////////////////////////////////
    // DUT
    floating_point_multiplier #(
        .EXP_WIDTH(EXP_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH)
    ) dut (
        .clk_i(clk),
        .rst_i(rst),

        .fp_a_i(bfm.fp_a_i),
        .fp_b_i(bfm.fp_b_i),
        .valid_i(bfm.valid_i),

        .fp_o(bfm.fp_o),
        .valid_o(bfm.valid_o)
    );

    initial begin
        ////////////////////////////////////////////////////////////////
        // generator
        static TriggerableQueueBroadcaster #(T) generator_out_broadcast = new();
        static FpGenerator32 #(T) generator = new(generator_out_broadcast);

        ////////////////////////////////////////////////////////////////
        // driver
        static TriggerableQueue #(T) driver_in_queue = new();
        static FpDriver32 #(T, I) driver = new(driver_in_queue, bfm);

        ////////////////////////////////////////////////////////////////
        // golden model
        static TriggerableQueue #(T) golden_in_queue = new();
        static TriggerableQueueBroadcaster #(T) golden_out_broadcast = new();
        static FpModel32 #(T,1) golden = new(golden_in_queue, golden_out_broadcast);

        ////////////////////////////////////////////////////////////////
        // monitor
        static TriggerableQueueBroadcaster #(T) monitor_out_broadcast = new();
        static FpMonitor32 #(T, I) monitor = new(monitor_out_broadcast, bfm);


        ////////////////////////////////////////////////////////////////
        // scoreboard
        static TriggerableQueue #(T) scoreboard_in_queue_dut = new();
        static TriggerableQueue #(T) scoreboard_in_queue_golden = new();
        static FpScoreboard32 #(T) scoreboard = new(scoreboard_in_queue_dut, scoreboard_in_queue_golden);

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
        //$dumpfile("waves.vcd");
        //$dumpvars(0, floating_point_multiplier_32_tb);

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
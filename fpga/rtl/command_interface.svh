`ifndef _COMMAND_INTERFACE_SVH
    `define _COMMAND_INTERFACE_SVH

/**
 * Command interface
 */
interface command_interface #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32
) (
    input clk
);
    logic [ADDR_WIDTH-1:0] addr;
    logic [DATA_WIDTH-1:0] data;
    logic valid;

    modport writer(input clk, input addr, input data, input valid);
endinterface

`endif
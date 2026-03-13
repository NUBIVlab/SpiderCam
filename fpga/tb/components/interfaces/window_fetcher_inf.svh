`ifndef WINDOW_FETCHER_INF  
    `define WINDOW_FETCHER_INF
interface window_fetcher_inf #(
    parameter DATA_WIDTH = 0,
    parameter WINDOW_WIDTH = 0,
    parameter WINDOW_HEIGHT = 0
) (
    input clk_i,
    input rst_i
);
    logic [DATA_WIDTH - 1 : 0] data_i;
    logic [15:0]               col_i;
    logic [15:0]               row_i;
    logic                      valid_i;

    logic [DATA_WIDTH - 1 : 0] window_o [WINDOW_HEIGHT][WINDOW_WIDTH];
    logic [15:0]               col_o;
    logic [15:0]               row_o;
    logic                      valid_o;

endinterface
`endif 
module stream_buffer #(
    parameter CHANNELS = 0,
    parameter DATA_WIDTH = 0,
    parameter BUFFER_DEPTH = 0,

    // local
    parameter BUFFER_DEPTH_CL2 = $clog2(BUFFER_DEPTH)
) (
    // Write Side
    input                       wr_clks_i      [CHANNELS],
    input                       wr_rsts_i      [CHANNELS],
    input  [DATA_WIDTH - 1 : 0] wr_channels_i  [CHANNELS],
    input                       wr_valids_i    [CHANNELS],
    input                       wr_sof_i,
    
    // Read Side
    input                       rd_clk_i,
    input                       rd_rst_i,
    input                       rd_stall_i,
    output [DATA_WIDTH - 1 : 0] rd_channels_o  [CHANNELS],
    output                      rd_valid_o,
    output                      rd_sof_o
);
    
    logic rd_valid;
    logic rd_valid_next;

    logic rd_en;
    logic rd_empty        [CHANNELS];
    logic rd_almost_empty [CHANNELS];
    logic rd_atlo_empty;
    logic rd_atlo_almost_empty;
    // 'atlo' is 'at least one'

    ////////////////////////////////////////////////////////////////
    // Reading Logic
    // we can read when both the buffer has something
    // and rd_stall_i is low.
    always_comb begin
        rd_atlo_empty        = 0;
        rd_atlo_almost_empty = 0;
        for(int c = 0; c < CHANNELS; c++) begin
            rd_atlo_empty = rd_atlo_empty | rd_empty[c];
            rd_atlo_almost_empty = rd_atlo_almost_empty | rd_almost_empty[c];
        end
        rd_en                = 0;
        rd_valid_next        = 0;

        if((!rd_atlo_empty) && (!rd_atlo_almost_empty) && (!rd_stall_i)) begin
            rd_en = 1;
            rd_valid_next = 1;
        end
    end

    always_ff @(posedge rd_clk_i) begin
        if(rd_rst_i) begin
            rd_valid <= 0;
        end else begin
            rd_valid <= rd_valid_next;
        end
    end 

    generate
        for(genvar c = 0; c < CHANNELS; c++) begin
            if(c == 0) begin
                // first channel also carries the sof bit
                async_fifo #(
                    .DSIZE(DATA_WIDTH + 1),
                    .ASIZE(BUFFER_DEPTH_CL2),
                    .FALLTHROUGH("FALSE")
                ) buffer_sof (
                    .wclk(wr_clks_i[c]), 
                    .wrst_n(!wr_rsts_i[c]),
                    .winc(wr_valids_i[c]), 
                    .wdata({wr_sof_i, wr_channels_i[c]}),
                    .wfull(), 
                    .awfull(),

                    .rclk(rd_clk_i), 
                    .rrst_n(!rd_rst_i),
                    .rinc(rd_en), 
                    .rdata({rd_sof_o, rd_channels_o[c]}),
                    .rempty(rd_empty[c]), 
                    .arempty(rd_almost_empty[c])
                );
            end else begin
                async_fifo #(
                    .DSIZE(DATA_WIDTH),
                    .ASIZE(BUFFER_DEPTH_CL2),
                    .FALLTHROUGH("FALSE")
                ) buffer_sof (
                    .wclk(wr_clks_i[c]), 
                    .wrst_n(!wr_rsts_i[c]),
                    .winc(wr_valids_i[c]), 
                    .wdata(wr_channels_i[c]),
                    .wfull(), 
                    .awfull(),

                    .rclk(rd_clk_i), 
                    .rrst_n(!rd_rst_i),
                    .rinc(rd_en), 
                    .rdata(rd_channels_o[c]),
                    .rempty(rd_empty[c]), 
                    .arempty(rd_almost_empty[c])
                );
            end
        end
    endgenerate
    assign rd_valid_o = rd_valid;
endmodule
/* Header Format - 14 words total (MAGIC_NUM_WORDS)
 * MAGIC_NUM  - 8 words
 * WIDTH      - 2 words
 * HEIGHT     - 2 words
 * CHANNELS   - 1 word
 * DATA_WIDTH - 1 word
 * 
 * Word size is DES_CHANNEL_DATA_WIDTH
 *
 * DATA_WIDTH must be a (greater) multiple
 * of DES_CHANNEL_DATA_WIDTH
 * 
 * the MAGIC_NUM is set to 'BIVFRAME' 
 * for the default scenario of DES_CHANNEL_WIDTH == 8.
 */

module stream_channel_deserializer #(
    // stream buffer params
    parameter CHANNELS = 0,
    parameter DATA_WIDTH = 0,
    parameter WIDTH = 0,
    parameter HEIGHT = 0,
    // single channel out data width
    parameter  DES_CHANNEL_DATA_WIDTH = 0,
    parameter [(DES_CHANNEL_DATA_WIDTH * 8)  - 1 : 0] MAGIC_NUM = 64'h42_49_56_46_52_41_4D_45,
                                                                 //  B  I  V  F  R  A  M  E

    // local
    parameter MAGIC_NUM_WORDS = 14,
    parameter [(DES_CHANNEL_DATA_WIDTH * 14) - 1 : 0] MAGIC_NUM_ALL = {MAGIC_NUM, 
                                                                       {WIDTH     [(DES_CHANNEL_DATA_WIDTH * 2) - 1 : 0]}, 
                                                                       {HEIGHT    [(DES_CHANNEL_DATA_WIDTH * 2) - 1 : 0]}, 
                                                                       {CHANNELS  [(DES_CHANNEL_DATA_WIDTH * 1) - 1 : 0]}, 
                                                                       {DATA_WIDTH[(DES_CHANNEL_DATA_WIDTH * 1) - 1 : 0]}},
    parameter PER_CHANNEL_PARTS = DATA_WIDTH / DES_CHANNEL_DATA_WIDTH,
    parameter TOTAL_PARTS = PER_CHANNEL_PARTS * CHANNELS
) (
    input rd_clk_i,
    input rd_rst_i,

    // Read Side
    output                                  rd_stall_o,
    input  [DATA_WIDTH - 1 : 0]             rd_channels_i [CHANNELS],
    input                                   rd_valid_i,
    input                                   rd_sof_i,

    // Write Side
    input                                   wr_stall_i,
    output [DES_CHANNEL_DATA_WIDTH - 1 : 0] wr_channel_o,
    output                                  wr_valid_o
);

    // zero latency buffer
    logic                      zlb_rd_en_i;
    logic [DATA_WIDTH - 1 : 0] zlb_channels_o [CHANNELS];
    logic                      zlb_valid_o;
    logic                      zlb_sof_o;

    zero_latency_buffer #(
        .CHANNELS(CHANNELS),
        .DATA_WIDTH(DATA_WIDTH)
    ) zero_latency_buffer_inst (
        .rd_clk_i(rd_clk_i),
        .rd_rst_i(rd_rst_i),

        .rd_stall_o(rd_stall_o),
        .rd_channels_i(rd_channels_i),
        .rd_valid_i(rd_valid_i),
        .rd_sof_i(rd_sof_i),

        .rd_en_i(zlb_rd_en_i),
        .channels_o(zlb_channels_o),
        .valid_o(zlb_valid_o),
        .sof_o(zlb_sof_o)
    );
    
    // state control
    logic unsigned [7:0] channel_idx;
    logic unsigned [7:0] channel_idx_next;

    logic unsigned [7:0] channel_part_idx;
    logic unsigned [7:0] channel_part_idx_next;

    logic unsigned [7:0] header_idx;
    logic unsigned [7:0] header_idx_next;

    logic header_done;
    logic header_done_next;

    logic as_sof;

    always_ff @(posedge rd_clk_i) begin
        if(rd_rst_i) begin
            channel_idx      <= 0;
            channel_part_idx <= PER_CHANNEL_PARTS - 1;
            header_idx       <= MAGIC_NUM_WORDS - 1;
            header_done      <= 0;
        end else begin
            channel_idx      <= channel_idx_next;
            channel_part_idx <= channel_part_idx_next;
            header_idx       <= header_idx_next;
            header_done      <= header_done_next;
        end
    end

    // output 
    logic [DES_CHANNEL_DATA_WIDTH - 1 : 0] channel;
    logic                                  valid;

    // By using the ZLB, we can essentially have a 
    // simple to use (almost) Moore Machine Deserializer
    always_comb begin
        channel_idx_next      = channel_idx;
        channel_part_idx_next = channel_part_idx;
        header_done_next      = header_done;
        header_idx_next       = header_idx;
        // should we treat this as a sof and process a header
        // or process the actual data associated with the sof bit?
        as_sof                = (!header_done) && zlb_sof_o; 

        valid       = 0;
        // either points to header or channels according to as_sof 
        channel     = as_sof ? MAGIC_NUM_ALL [(DES_CHANNEL_DATA_WIDTH) * header_idx +: 
                                              (DES_CHANNEL_DATA_WIDTH)]:
                               zlb_channels_o[channel_idx]
                                             [(DES_CHANNEL_DATA_WIDTH) * channel_part_idx +: 
                                              (DES_CHANNEL_DATA_WIDTH)];
        zlb_rd_en_i = 0;

        // HEADER
        if (zlb_valid_o && as_sof) begin
            if(!wr_stall_i) begin
                valid = 1;
                header_idx_next = header_idx - 1;
                if(header_idx == 0) begin
                    header_idx_next = MAGIC_NUM_WORDS - 1;
                    // we've reached the end of the header, however, we need to 
                    // process the actual sof data itself! Hence, we use the header_done flag
                    header_done_next = 1;
                end
            end
        end

        // BODY
        else if(zlb_valid_o) begin
            if(!wr_stall_i) begin
                valid = 1;
                channel_part_idx_next = channel_part_idx - 1;
                if(channel_part_idx == 0) begin
                    channel_part_idx_next = PER_CHANNEL_PARTS - 1;
                    channel_idx_next = channel_idx + 1;
                    // we've reached the end, need to push out the data and potentially
                    // start deserializing the next data, this is also the right time to 
                    // reset header_done to 0
                    if(channel_idx == (CHANNELS - 1)) begin
                        channel_idx_next = 0;
                        zlb_rd_en_i = 1;
                        header_done_next = 0;
                    end
                end
            end 
        end
    end

    assign wr_channel_o = channel;
    assign wr_valid_o = valid;
endmodule
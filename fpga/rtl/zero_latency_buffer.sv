/*
 * Designed to work with stream_channel_deserializer
 * It takes time to read from a FIFO,
 * and with the ability to stall, gets a bit
 * complicated, so use this latency buffer which is
 * basically a true zero latency FWFT fifo.
 *
 * What this means is valid_o says wether there
 * is data available (with zero latency) and 
 * setting rd_en will push it out. rd_stall_o
 * will tell the buffer its reading from to
 * stop pusing data out (which prevents overflow).
 * 
 * Using a read and write pointer seems sensible, 
 * however, the read pointer muxing what register to pass 
 * is itself a source of latency. So instead we use
 * something like a stack queue or 'collapsing' stack.
 *
 */

module zero_latency_buffer #(
    parameter CHANNELS = 0,
    parameter DATA_WIDTH = 0
) (
    input rd_clk_i,
    input rd_rst_i,

    // Read Side Buffer 
    output                      rd_stall_o,
    input  [DATA_WIDTH - 1 : 0] rd_channels_i [CHANNELS],
    input                       rd_valid_i,
    input                       rd_sof_i,

    // Zero Latency Read Side
    input                       rd_en_i,
    output [DATA_WIDTH - 1 : 0] channels_o    [CHANNELS],
    output                      valid_o,
    output                      sof_o
);
    // buffers
    logic sof_latency_buffer      [8];
    logic sof_latency_buffer_next [8];

    logic [DATA_WIDTH - 1 : 0] channels_latency_buffer      [8][CHANNELS];
    logic [DATA_WIDTH - 1 : 0] channels_latency_buffer_next [8][CHANNELS];

    // control state
    logic unsigned [2:0] stack_count;
    logic unsigned [2:0] stack_count_next;

    logic stall;
    logic stall_next;

    logic valid;
    logic valid_next;

    // input registers
    logic [DATA_WIDTH - 1 : 0] rd_channels_reg [CHANNELS];
    logic                      rd_valid_reg;
    logic                      rd_sof_reg;

    always_comb begin
        // defaults
        stack_count_next = stack_count;
        sof_latency_buffer_next = sof_latency_buffer;
        channels_latency_buffer_next = channels_latency_buffer;
        

        // 3 distinct cases
        if          (rd_valid_reg && (!rd_en_i)) begin
            // push onto stack
            sof_latency_buffer_next     [stack_count] = rd_sof_reg;
            channels_latency_buffer_next[stack_count] = rd_channels_reg;
            // stack count increments by 1
            stack_count_next                          = stack_count + 1;
        end else if (rd_valid_reg && rd_en_i) begin
            // push onto stack
            sof_latency_buffer_next     [stack_count] = rd_sof_reg;
            channels_latency_buffer_next[stack_count] = rd_channels_reg;
            // pop from front of stack
            for(int i = 0; i < 7; i++) begin
                sof_latency_buffer_next     [i] = sof_latency_buffer[i+1];
                channels_latency_buffer_next[i] = channels_latency_buffer[i+1];
            end
            // stack count remains the same (1-1)
        end else if ((!rd_valid_reg) && rd_en_i) begin
            // pop from front of stack
            for(int i = 0; i < 7; i++) begin
                sof_latency_buffer_next     [i] = sof_latency_buffer[i+1];
                channels_latency_buffer_next[i] = channels_latency_buffer[i+1];
            end
            // stack count decrements by 1
            stack_count_next = stack_count - 1;
        end else begin
            // Do nothing
        end

        // valid condition
        valid_next = stack_count_next > 0 ? 1 : 0;
        // stall condition
        stall_next = stack_count_next >= 4 ? 1 : 0;
    end
    
    assign channels_o = channels_latency_buffer[0];
    assign sof_o      = sof_latency_buffer[0];
    assign valid_o    = valid;
    assign rd_stall_o = stall;

    always_ff @(posedge rd_clk_i) begin
        sof_latency_buffer      <= sof_latency_buffer_next;
        channels_latency_buffer <= channels_latency_buffer_next;
        rd_channels_reg         <= rd_channels_i;
        rd_sof_reg              <= rd_sof_i;
        if(rd_rst_i) begin
            rd_valid_reg <= 0;
            stack_count  <= 0;
            valid        <= 0;
            stall        <= 1;
        end else begin
            rd_valid_reg <= rd_valid_i;
            stack_count  <= stack_count_next;
            valid        <= valid_next;
            stall        <= stall_next;
        end
    end

endmodule
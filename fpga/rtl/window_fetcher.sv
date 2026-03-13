/* Window Fetcher 
 * Accepts an image of data in a streaming fashion and outputs the corresponding
 * window following the 'push in to push out' model.
 *
 * For values lying outside the image width, we extend the border with a constant set
 * by BORDER_EXTENSION_CONSTANT. Having this enabled uses more resources and increases
 * the latency by once cycle. This can be toggled with BORDER_ENABLE.
 *
 * The window is comes out natively reversed since pixels flow left to right and up to
 * down into the window. We 'rewire' (really just a logical remapping no actually wires
 * are produced) at the end to reverse this flipping. That being said, the calculated
 * centers are for the reversed window, and so to find the true center, reverse the 
 * window to see where the center maps. The starting center is biased towards
 * top left (then the offset is applied to see the final location).
 *
 * The user doesn't have to worry about this when setting the offsets, for example:
 *
 * WINDOW_WIDTH  = 6
 * WINDOW_HEIGHT = 5
 *
 * WINDOW_WIDTH_CENTER_OFFSET  = -1
 * WINDOW_HEIGHT_CENTER_OFFSET = 2
 * (co - center without offset, cx - center with offset)
 *
 * User expectation:
 * [[  ,  ,  ,  ,  ,  ],
 *  [  ,  ,  ,  ,  ,  ],
 *  [  ,  ,co,  ,  ,  ],
 *  [  ,  ,  ,  ,  ,  ],
 *  [  ,cx,  ,  ,  ,  ],
 * ]
 *
 * Reverse center:
 * [[  ,  ,  ,  ,cx,  ],
 *  [  ,  ,  ,  ,  ,  ],
 *  [  ,  ,  ,co,  ,  ],
 *  [  ,  ,  ,  ,  ,  ],
 *  [  ,  ,  ,  ,  ,  ],
 * ]
 * 
 * then reversed rewiring
 *
 * [[  ,  ,  ,  ,  ,  ],
 *  [  ,  ,  ,  ,  ,  ],
 *  [  ,  ,co,  ,  ,  ],
 *  [  ,  ,  ,  ,  ,  ],
 *  [  ,cx,  ,  ,  ,  ],
 * ]
 * which matches user expectation.
 */

module window_fetcher #(
    parameter DATA_WIDTH,

    parameter IMAGE_WIDTH,
    parameter IMAGE_HEIGHT,

    parameter WINDOW_WIDTH,
    parameter WINDOW_HEIGHT,
    parameter WINDOW_WIDTH_CENTER_OFFSET  = 0,
    parameter WINDOW_HEIGHT_CENTER_OFFSET = 0,

    parameter [DATA_WIDTH - 1 : 0] BORDER_EXTENSION_CONSTANT = 0,
    parameter                      BORDER_ENABLE             = 1,

    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter WINDOW_WIDTH_CENTER  = ((WINDOW_WIDTH - 1)  / 2) + WINDOW_WIDTH_CENTER_OFFSET,
    parameter WINDOW_HEIGHT_CENTER = ((WINDOW_HEIGHT - 1) / 2) + WINDOW_HEIGHT_CENTER_OFFSET,

    parameter WINDOW_WIDTH_CENTER_REVERSE  = (WINDOW_WIDTH - 1)  - WINDOW_WIDTH_CENTER,
    parameter WINDOW_HEIGHT_CENTER_REVERSE = (WINDOW_HEIGHT - 1) - WINDOW_HEIGHT_CENTER,

    parameter WINDOW_WIDTH_CENTER_START  = (IMAGE_WIDTH  - 1) - WINDOW_WIDTH_CENTER_REVERSE,
    parameter WINDOW_HEIGHT_CENTER_START = (IMAGE_HEIGHT - 1) - WINDOW_HEIGHT_CENTER_REVERSE,

    parameter BUFFER_LINES = WINDOW_HEIGHT - 1,
    parameter BUFFER_DEPTH = $clog2(IMAGE_WIDTH + 3)
) (
    input clk_i,
    input rst_i,

    input  [DATA_WIDTH - 1 : 0] data_i,
    input  [15:0]               col_i,
    input  [15:0]               row_i,
    input                       valid_i,

    output [DATA_WIDTH - 1 : 0] window_o [WINDOW_HEIGHT][WINDOW_WIDTH],
    output [15:0]               col_o,
    output [15:0]               row_o,
    output                      valid_o
);
    logic [DATA_WIDTH - 1 : 0] data;
    logic [15 : 0]             col;
    logic [15 : 0]             row;
    logic                      valid;
    
    always_ff@(posedge clk_i) begin
        data <= data_i;
        col  <= col_i;
        row  <= row_i;
        if(rst_i) begin
            valid <= 0;
        end else begin
            valid <= valid_i;
        end
    end       
    
    // small sync logic
    logic sof;
    assign sof = (col == 0) && (row == 0) && valid;
    logic [15:0] window_width_center_start_next;
    logic [15:0] window_height_center_start_next;

    ////////////////////////////////////////////////////////////////
    // Control State
    logic [15:0] window_center_col;
    logic [15:0] window_center_row;

    logic [15:0] window_center_col_next;
    logic [15:0] window_center_row_next;

    logic [15:0] window_center_col_latent;
    logic [15:0] window_center_row_latent;

    logic [15:0] window_center_col_latent_next;
    logic [15:0] window_center_row_latent_next;

    logic initial_start;
    logic initial_start_next;

    always_ff@(posedge clk_i) begin
        if(rst_i) begin
            window_center_col <= WINDOW_WIDTH_CENTER_START;
            window_center_row <= WINDOW_HEIGHT_CENTER_START;
            initial_start     <= 0;
        end else begin
            window_center_row <= window_center_row_next;
            window_center_col <= window_center_col_next;
            initial_start     <= initial_start_next;
        end
    end

    always_comb begin
        // sync setting
        window_width_center_start_next = WINDOW_WIDTH_CENTER_START;
        window_height_center_start_next = WINDOW_HEIGHT_CENTER_START;
        if(window_width_center_start_next == (IMAGE_WIDTH - 1)) begin
            window_width_center_start_next = 0;
            if(window_height_center_start_next == (IMAGE_HEIGHT - 1)) begin
                window_height_center_start_next = 0;
            end else begin
                window_height_center_start_next = window_height_center_start_next + 1;
            end
        end else begin
            window_width_center_start_next = window_width_center_start_next + 1;
        end  

        window_center_col_next = window_center_col;
        window_center_row_next = window_center_row;
        initial_start_next     = initial_start; 

        if(valid) begin
            window_center_col_next = window_center_col + 1;
            if(window_center_col == (IMAGE_WIDTH - 1)) begin
                window_center_col_next = 0;
                window_center_row_next = window_center_row + 1;
                if(window_center_row == (IMAGE_HEIGHT - 1)) begin
                    window_center_row_next = 0;
                end
            end
            if(sof) begin
                window_center_col_next = window_width_center_start_next;
                window_center_row_next = window_height_center_start_next;
            end
            if((window_center_col == (IMAGE_WIDTH - 1)) && (window_center_row == (IMAGE_HEIGHT - 1))) begin
                initial_start_next = 1;
            end 
        end
    end

    ////////////////////////////////////////////////////////////////
    // Window Shift Registers and Buffers
    logic [DATA_WIDTH - 1 : 0] window_reversed [WINDOW_HEIGHT][WINDOW_WIDTH];
    logic [DATA_WIDTH - 1 : 0] window          [WINDOW_HEIGHT][WINDOW_WIDTH];
    
    logic [15:0] pointer_separation;
    logic [15:0] pointer_separation_next;

    always_ff@(posedge clk_i) begin
        if(rst_i) begin
            pointer_separation <= 0;
        end else begin
            pointer_separation <= pointer_separation_next;
        end
    end

    logic                      w_rst_n      ;
    logic                      w_wr         ;
    logic [DATA_WIDTH - 1 : 0] w_data       [WINDOW_HEIGHT];
    
    logic                      r_rst_n      ;
    logic                      r_rd         ;
    logic [DATA_WIDTH - 1 : 0] r_data       [WINDOW_HEIGHT];

    always_comb begin
        w_rst_n  = ~rst_i;
        w_wr     = valid;
        r_rst_n  = ~rst_i;
        r_rd     = 0;
        pointer_separation_next = pointer_separation;

        if(valid) begin
            if(pointer_separation == (IMAGE_WIDTH - 1)) begin
                r_rd = 1;
            end else begin
                pointer_separation_next = pointer_separation + 1;
            end
        end

        w_data[0] = data;
        for(int r = 1; r < WINDOW_HEIGHT; r++) begin
            w_data[r] = r_data[r - 1];
        end
    end

    always_ff@(posedge clk_i) begin
        if(rst_i) begin
            for(int r = 0; r < WINDOW_HEIGHT; r++) begin
                for(int c = 0; c < WINDOW_WIDTH; c++) begin
                    window_reversed[r][c] <= 0;
                end
            end
        end else begin
            if(valid) begin
                window_reversed[0][0] <= data;
                for(int r = 0; r < WINDOW_HEIGHT; r++) begin
                    for(int c = 1; c < WINDOW_WIDTH; c++) begin
                        window_reversed[r][c] <= window_reversed[r][c-1];
                    end
                end
                for(int r = 1; r < WINDOW_HEIGHT; r++) begin
                    window_reversed[r][0] <= r_data[r-1]; 
                end

            end else begin
                for(int r = 0; r < WINDOW_HEIGHT; r++) begin
                    for(int c = 0; c < WINDOW_WIDTH; c++) begin
                        window_reversed[r][c] <= window_reversed[r][c];
                    end
                end
            end
        end
    end

    generate 
        for(genvar b = 0; b < BUFFER_LINES; b++) begin
            async_fifo #(
                .DSIZE(DATA_WIDTH),
                .ASIZE(BUFFER_DEPTH),
                .FALLTHROUGH("FALSE")
            ) row_buffer (
                .wclk   (clk_i), 
                .wrst_n (w_rst_n),
                .winc   (w_wr), 
                .wdata  (w_data[b]),
                .wfull  (), 
                .awfull (),

                .rclk   (clk_i), 
                .rrst_n (r_rst_n),
                .rinc   (r_rd), 
                .rdata  (r_data[b]),
                .rempty (), 
                .arempty()
            );
        end

        for(genvar r = 0; r < WINDOW_HEIGHT; r++) begin
            for(genvar c = 0; c < WINDOW_WIDTH; c++) begin
                assign window[r][c] = window_reversed[(WINDOW_HEIGHT - 1) - r][(WINDOW_WIDTH - 1) - c];
            end
        end
    endgenerate 

    ////////////////////////////////////////////////////////////////
    // Border Constant Extension
    logic [DATA_WIDTH - 1 : 0] window_0 [WINDOW_HEIGHT][WINDOW_WIDTH];
    logic [15:0]               window_center_col_0;
    logic [15:0]               window_center_row_0;
    logic                      valid_0;

    always_ff@(posedge clk_i) begin
        if(BORDER_ENABLE) begin
            window_0               <= window;
            window_center_col_0    <= window_center_col;
            window_center_row_0    <= window_center_row;
            if(rst_i) begin
                valid_0 <= 0;
            end else begin
                valid_0 <= valid && initial_start;
            end
        end
    end

    logic [DATA_WIDTH - 1 : 0] window_border_constant [WINDOW_HEIGHT][WINDOW_WIDTH];
    always_comb begin
        if(BORDER_ENABLE) begin
            for(int r = 0; r < WINDOW_HEIGHT; r++) begin
                for(int c = 0; c < WINDOW_WIDTH; c++) begin
                    int c_center_dist;
                    int r_center_dist;
                    logic [15:0] c_img; 
                    logic [15:0] r_img;
                    c_center_dist = c - WINDOW_WIDTH_CENTER;
                    r_center_dist = r - WINDOW_HEIGHT_CENTER;
                    c_img = window_center_col_0 + c_center_dist; 
                    r_img = window_center_row_0 + r_center_dist;
        
                    if((r_img < 0) || (r_img > (IMAGE_HEIGHT - 1)) || (c_img < 0) || (c_img > (IMAGE_WIDTH  - 1))) begin
                        window_border_constant[r][c] = BORDER_EXTENSION_CONSTANT;
                    end else begin
                        window_border_constant[r][c] = window_0[r][c];
                    end

                end
            end
        end
    end

    assign window_o = BORDER_ENABLE ? window_border_constant : window;
    assign col_o    = BORDER_ENABLE ? window_center_col_0    : window_center_col;
    assign row_o    = BORDER_ENABLE ? window_center_row_0    : window_center_row;
    assign valid_o  = BORDER_ENABLE ? valid_0                : valid && initial_start;
endmodule
/* Region of Interest (ROI)
 * 
 * Given a stream of pixels, only outputs
 * the pixels that are within the region
 * of interest set by runtime inputs:
 * - [row_start, row_end]
 * - [col_start, col_end]
 *
 * i.e 640x480 image where i just want the
 * bottom left quadrant. The output will 
 * go from the nominal 0 -> 239 row
 * and 0 -> 319 range, the parameters are
 * row_start = 240, row_end = 439
 * col_start = 0,   col_end = 319
 *
 * This is frame synchronized, meaning changes
 * to the boundaries will be updated after
 * the end of a frame.
 */

module roi (
    pixel_data_interface.writer in,
    pixel_data_interface.reader out,

    // runtime boundaries
    input [15:0] row_start_i,
    input [15:0] row_end_i,
    input [15:0] col_start_i,
    input [15:0] col_end_i,

    // reset signal 
    input rst_n_i
);
    logic [15:0] r_row_start;
    logic [15:0] r_row_end;
    logic [15:0] r_col_start;
    logic [15:0] r_col_end;

    logic [15:0] r_row_start_next;
    logic [15:0] r_row_end_next;
    logic [15:0] r_col_start_next;
    logic [15:0] r_col_end_next;

    logic init_bool;
    logic init_bool_next;

    logic [15:0] r_row;
    logic [15:0] r_col;
    logic r_valid;
    logic [in.FP_M+in.FP_N+in.FP_S-1:0] r_pixel;

    logic [15:0] r_row_o;
    logic [15:0] r_col_o;
    logic r_valid_o;
    logic [in.FP_M+in.FP_N+in.FP_S-1:0] r_pixel_o;

    logic [15:0] r_row_o_next;
    logic [15:0] r_col_o_next;
    logic r_valid_o_next;
    logic [in.FP_M+in.FP_N+in.FP_S-1:0] r_pixel_o_next;

    always_comb begin
        // Boundary update logic 
        init_bool_next = init_bool;
        r_row_start_next = r_row_start;
        r_row_end_next   = r_row_end;
        r_col_start_next = r_col_start;
        r_col_end_next   = r_col_end;

        if((r_row_start != row_start_i) || (r_row_end != row_end_i) ||
           (r_col_start != col_start_i) || (r_col_end != col_end_i)) begin
            if((init_bool == 0) || ((r_row == r_row_end) && (r_col == r_col_end) && (r_valid == 1))) begin
                init_bool_next = 1;
                r_row_start_next = row_start_i;
                r_row_end_next = row_end_i;
                r_col_start_next = col_start_i;
                r_col_end_next = col_end_i;
            end 
        end

        r_row_o_next = r_row - r_row_start;
        r_col_o_next = r_col - r_col_start;
        r_valid_o_next = 0;
        r_pixel_o_next = r_pixel;

        if(r_valid == 1) begin
            if((r_row >= row_start_i) && (r_row <= row_end_i) && 
               (r_col >= col_start_i) && (r_col <= col_end_i)) begin
                r_valid_o_next = r_valid;
            end
        end

        //reset logic
        if(!rst_n_i) begin
            r_row_start_next = 0;
            r_row_end_next = 32767;
            r_col_start_next = 0;
            r_col_end_next = 32767;
            init_bool_next = 0;
        end
    end

    always@(posedge in.clk) begin
        init_bool   <= init_bool_next;
        r_row_start <= r_row_start_next;
        r_row_end   <= r_row_end_next;
        r_col_start <= r_col_start_next;
        r_col_end   <= r_col_end_next;

        if(!rst_n_i) begin
            r_valid <= 0;
        end else begin
            r_valid <= in.valid;
        end

        r_row <= in.row;
        r_col <= in.col;
        r_pixel <= in.pixel;

        r_row_o <= r_row_o_next;
        r_col_o <= r_col_o_next;
        r_valid_o <= r_valid_o_next;
        r_pixel_o <= r_pixel_o_next;
    end

    assign out.row = r_row_o;
    assign out.col = r_col_o;
    assign out.valid = r_valid_o;
    assign out.pixel = r_pixel_o;

endmodule
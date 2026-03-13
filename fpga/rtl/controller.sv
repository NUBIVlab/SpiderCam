/*
 * Simple Controller that drives the constants
 * and two bilinear xform matrix values
 * Memory Map:
 * Homography matricies
 * ----------------------------
 * 0x10 -> 0x18 - Bilinear transform matrix for camera 0
 * 0x20 -> 0x28 - Bilinear transform matrix for camera 1
 *
 * Roi boundaries
 * ----------------------------
 * All roi's are fixed size - their dims are determined
 * (0x80, 0x81) - top-left corner of roi pre-bilinear-xform roi (y, x). roi is fixed-size
 * (0x82, 0x83) - top-left corner of roi post-bilinear-xform roi (y, x).
 *
 *
 * DfDD constants, 2 scale setup - each 2 bytes
 * ----------------------------
 * A and B are variable, with 16 zones
 *
 * 0xA0 -> 0xAF - Scale 0, A values per zone
 * 0x90 -> 0x9F - Scale 1, A values per zone
 * 0xB0 -> 0xBF - Scale 0, B values per zone
 * 0xF0 -> 0xFF - Scale 1, B values per zone
 * 0x70 -> 0x7F - radius squared values
 * 0xC0 -> 0xC1 - w0
 * 0xD0 -> 0xD1 - w1
 * 0xE0 -> 0xE1 - w2
 * 
 * Confidence Minimum, 16 zones
 * ----------------------------
 * 0x50 -> 0x5F - 2 bytes
 *
 * Depth Maximum, 16 zones
 * ----------------------------
 * 0x00 -> 0x0F - 2 bytes
 * 
 * Depth Minimum, 16 zones
 * ----------------------------
 * 0x30 -> 0x3F
 *
 *
 *
 * Col and Row center
 * ----------------------------
 * 0x60 - col center
 * 0x61 - row center
 *
 * rest has no effect.
 *
 * Default (reset) parameters should be fully defined.
 */

module controller #(
    parameter FP_M_K = 2,
    parameter FP_N_K = 12,
    parameter FP_S_K = 1,

    parameter PRECISION = 0,

    // Default Values for Constants
    parameter [15:0] A  [2][16] = {default: 16'h3c00},

    parameter [15:0] B  [2][16] = {default: 16'h3c00},

    parameter [17:0] R_SQUARED[16] = '{default : 16'h0000},

    parameter [15:0] COL_CENTER = 16'h00C8,
    parameter [15:0] ROW_CENTER = 16'h00C8,

    parameter [15:0] W0 [2] = '{16'h3c00, 16'h3c00},
    parameter [15:0] W1 [2] = '{16'h3c00, 16'h3c00},
    parameter [15:0] W2 [2] = '{16'h3c00, 16'h3c00},

    parameter [15:0] DEFAULT_CONFIDENCE_MINIMUM [16] = '{default : 16'h0000},
    parameter [15:0] DEFAULT_DEPTH_MAXIMUM [16] = '{default : 16'h7fff},
    parameter [15:0] DEFAULT_DEPTH_MINIMUM [16] = '{default : 16'h0000},

    // default values for ROIs
    parameter logic [15:0] DEFAULT_PRE_XFORM_ROI_CORNER [2] = '{ 0, 0},
    parameter logic [15:0] DEFAULT_POST_XFORM_ROI_CORNER [2] = '{ 0, 0},

    // fixed height and width for ROIs
    parameter logic [15:0] PRE_XFORM_ROI_DIMS [2] = '{480, 512},
    parameter logic [15:0] POST_XFORM_ROI_DIMS [2] = '{480, 512},

    // default values for bilinear matrices
    parameter [11+PRECISION-1:0] BILINEAR_1 = 19'b000_0000_0001_0000_0000,
    parameter [11+PRECISION-1:0] DEFAULT_BILINEAR_MATRICES [3][3]
        = '{{BILINEAR_1,0,0},{0,BILINEAR_1,0},{0,0,BILINEAR_1}}
) (
    input rst_n_i,

    command_interface.writer in,

    output [15:0] a_o            [2][16],
    output [15:0] b_o            [2][16],
    output [17:0] r_squared_o       [16],
    output [15:0] w0_o [2],
    output [15:0] w1_o [2],
    output [15:0] w2_o [2],
    output [15:0] col_center_o,
    output [15:0] row_center_o,

    output [11+PRECISION-1:0] bilinear_matrices_o [2][3][3],

    // top, bottom, left, right
    output logic [15:0] pre_bilinear_roi_boundaries_o [4],
    output logic [15:0] post_bilinear_roi_boundaries_o [4],

    output [15:0] confidence_o [16],
    output [15:0] depth_o [16],
    output [15:0] depth_min_o [16]
);
    localparam CONST_WIDTH = FP_M_K + FP_N_K + FP_S_K;
    localparam MATRIX_WIDTH = 11 + PRECISION;

    logic [in.ADDR_WIDTH-1:0] addr;
    logic [in.DATA_WIDTH-1:0] data;
    logic valid;

    logic [15:0] addr_next;
    logic [31:0] data_next;
    logic valid_next;

    logic [15:0] a  [2][16];
    logic [15:0] b  [2][16];
    logic [17:0] r_squared [16];
    logic [15:0] col_center;
    logic [15:0] row_center;
    logic [15:0] w0 [2];
    logic [15:0] w1 [2];
    logic [15:0] w2 [2];

    logic [15:0] a_next  [2][16];
    logic [15:0] b_next  [2][16];
    logic [17:0] r_squared_next [16];
    logic [15:0] col_center_next;
    logic [15:0] row_center_next;
    logic [15:0] w0_next [2];
    logic [15:0] w1_next [2];
    logic [15:0] w2_next [2];

    logic [MATRIX_WIDTH-1:0] bilinear_matrices [2][3][3];
    logic [MATRIX_WIDTH-1:0] bilinear_matrices_next [2][3][3];

    logic [15:0] pre_bilinear_roi_corner [2];
    logic [15:0] post_bilinear_roi_corner [2];
    logic [15:0] pre_bilinear_roi_corner_next [2];
    logic [15:0] post_bilinear_roi_corner_next [2];

    logic [15:0] confidence [16];
    logic [15:0] confidence_next [16];

    logic [15:0] depth [16];
    logic [15:0] depth_next [16];

    logic [15:0] depth_min [16];
    logic [15:0] depth_min_next [16];

    always_comb begin
        int i, j ,k;

        addr_next = in.addr;
        data_next = in.data;
        valid_next = in.valid;

        a_next = a;
        b_next = b;
        r_squared_next = r_squared;
        col_center_next = col_center;
        row_center_next = row_center;
        w0_next = w0;
        w1_next = w1;
        w2_next = w2;

        bilinear_matrices_next = bilinear_matrices;

        pre_bilinear_roi_corner_next = pre_bilinear_roi_corner;
        post_bilinear_roi_corner_next = post_bilinear_roi_corner;

        confidence_next = confidence;
        depth_next = depth;
        depth_min_next = depth_min;

        // Memory Mappings (written purposefully with independent if statements rather than case)
        if(valid) begin

        // matrix A
        if (addr == 16'h10) bilinear_matrices_next[0][0][0] = data[MATRIX_WIDTH-1:0];
        if (addr == 16'h11) bilinear_matrices_next[0][0][1] = data[MATRIX_WIDTH-1:0];
        if (addr == 16'h12) bilinear_matrices_next[0][0][2] = data[MATRIX_WIDTH-1:0];

        if (addr == 16'h13) bilinear_matrices_next[0][1][0] = data[MATRIX_WIDTH-1:0];
        if (addr == 16'h14) bilinear_matrices_next[0][1][1] = data[MATRIX_WIDTH-1:0];
        if (addr == 16'h15) bilinear_matrices_next[0][1][2] = data[MATRIX_WIDTH-1:0];

        if (addr == 16'h16) bilinear_matrices_next[0][2][0] = data[MATRIX_WIDTH-1:0];
        if (addr == 16'h17) bilinear_matrices_next[0][2][1] = data[MATRIX_WIDTH-1:0];
        if (addr == 16'h18) bilinear_matrices_next[0][2][2] = data[MATRIX_WIDTH-1:0];

        // matrix B
        if (addr == 16'h20) bilinear_matrices_next[1][0][0] = data[MATRIX_WIDTH-1:0];
        if (addr == 16'h21) bilinear_matrices_next[1][0][1] = data[MATRIX_WIDTH-1:0];
        if (addr == 16'h22) bilinear_matrices_next[1][0][2] = data[MATRIX_WIDTH-1:0];

        if (addr == 16'h23) bilinear_matrices_next[1][1][0] = data[MATRIX_WIDTH-1:0];
        if (addr == 16'h24) bilinear_matrices_next[1][1][1] = data[MATRIX_WIDTH-1:0];
        if (addr == 16'h25) bilinear_matrices_next[1][1][2] = data[MATRIX_WIDTH-1:0];

        if (addr == 16'h26) bilinear_matrices_next[1][2][0] = data[MATRIX_WIDTH-1:0];
        if (addr == 16'h27) bilinear_matrices_next[1][2][1] = data[MATRIX_WIDTH-1:0];
        if (addr == 16'h28) bilinear_matrices_next[1][2][2] = data[MATRIX_WIDTH-1:0];

        // col and row centers
        if (addr == 16'h60) col_center_next = data[15:0];
        if (addr == 16'h61) row_center_next = data[15:0];

        // camera 0 ROI settings
        if (addr == 16'h80) pre_bilinear_roi_corner_next[0] = data[15:0];
        if (addr == 16'h81) pre_bilinear_roi_corner_next[1] = data[15:0];
        if (addr == 16'h82) post_bilinear_roi_corner_next[0] = data[15:0];
        if (addr == 16'h83) post_bilinear_roi_corner_next[1] = data[15:0];

        // w0
        if(addr == 16'hc0) w0_next[0] = data[15:0];
        if(addr == 16'hc1) w0_next[1] = data[15:0];

        // w1
        if(addr == 16'hd0) w1_next[0] = data[15:0];
        if(addr == 16'hd1) w1_next[1] = data[15:0];
        
        // w2
        if(addr == 16'he0) w2_next[0] = data[15:0];
        if(addr == 16'he1) w2_next[1] = data[15:0];

        // Scale 0 - A
        i = 0;
        for(int a = 16'hA0; a < 16'hB0; a++) begin
            if(addr == a[15:0]) begin
                a_next[0][i] = data[15:0];
            end
            i++;
        end

        // Scale 1 - A
        i = 0;
        for(int a = 16'h90; a < 16'hA0; a++) begin
            if(addr == a[15:0]) begin
                a_next[1][i] = data[15:0];
            end
            i++;
        end

        // Scale 0 - B
        i = 0;
        for(int a = 16'hB0; a < 16'hC0; a++) begin
            if(addr == a[15:0]) begin
                b_next[0][i] = data[15:0];
            end
            i++;
        end

        // Scale 1 - B
        i = 0;
        for(int a = 16'hF0; a <= 16'hFF; a++) begin
            if(addr == a[15:0]) begin
                b_next[1][i] = data[15:0];
            end
            i++;
        end

        // r squared
        i = 0;
        for(int a = 16'h70; a < 16'h80; a++) begin
            if(addr == a[15:0]) begin
                r_squared_next[i] = data[17:0];
            end
            i++;
        end

        // confidence minimum
        i = 0;
        for(int a = 16'h50; a < 16'h60; a++) begin
            if(addr == a[15:0]) begin
                confidence_next[i] = data[15:0];
            end 
            i++;
        end

        // depth maximum
        i = 0;
        for(int a = 16'h00; a < 16'h10; a++) begin
            if(addr == a[15:0]) begin
                depth_next[i] = data[15:0];
            end 
            i++;
        end

        // depth minimum
        i = 0;
        for(int a = 16'h30; a < 16'h40; a++) begin
            if(addr == a[15:0]) begin
                depth_min_next[i] = data[15:0];
            end 
            i++;
        end

        // 

        end

        if(!rst_n_i) begin
            valid_next = 0;
            addr_next = 0;
            data_next = 0;

            a_next  = A;
            b_next  = B;
            r_squared_next =  R_SQUARED;
            w0_next = W0;
            w1_next = W1;
            w2_next = W2;

            col_center_next = COL_CENTER;
            row_center_next = ROW_CENTER;

            confidence_next = DEFAULT_CONFIDENCE_MINIMUM;
            depth_next = DEFAULT_DEPTH_MAXIMUM;
            depth_min_next = DEFAULT_DEPTH_MINIMUM;

            bilinear_matrices_next[0] = DEFAULT_BILINEAR_MATRICES;
            bilinear_matrices_next[1] = DEFAULT_BILINEAR_MATRICES;

            pre_bilinear_roi_corner_next = DEFAULT_PRE_XFORM_ROI_CORNER;
            post_bilinear_roi_corner_next = DEFAULT_POST_XFORM_ROI_CORNER;
        end
    end

    always@(posedge in.clk) begin
        addr <= addr_next;
        data <= data_next;
        valid <= valid_next;

        a  <= a_next;
        b  <= b_next;
        r_squared <= r_squared_next;
        w0 <= w0_next;
        w1 <= w1_next;
        w2 <= w2_next;

        col_center <= col_center_next;
        row_center <= row_center_next;

        bilinear_matrices <= bilinear_matrices_next;

        confidence <= confidence_next;
        depth <= depth_next;
        depth_min <= depth_min_next;

        pre_bilinear_roi_corner <= pre_bilinear_roi_corner_next;
        post_bilinear_roi_corner <= post_bilinear_roi_corner_next;

        pre_bilinear_roi_boundaries_o[0] <= pre_bilinear_roi_corner[0];
        pre_bilinear_roi_boundaries_o[1] <= pre_bilinear_roi_corner[0] + PRE_XFORM_ROI_DIMS[0];
        pre_bilinear_roi_boundaries_o[2] <= pre_bilinear_roi_corner[1];
        pre_bilinear_roi_boundaries_o[3] <= pre_bilinear_roi_corner[1] + PRE_XFORM_ROI_DIMS[1];

        post_bilinear_roi_boundaries_o[0] <= post_bilinear_roi_corner[0];
        post_bilinear_roi_boundaries_o[1] <= post_bilinear_roi_corner[0] + POST_XFORM_ROI_DIMS[0];
        post_bilinear_roi_boundaries_o[2] <= post_bilinear_roi_corner[1];
        post_bilinear_roi_boundaries_o[3] <= post_bilinear_roi_corner[1] + POST_XFORM_ROI_DIMS[1];
    end

    assign a_o  = a;
    assign b_o  = b;
    assign r_squared_o = r_squared;
    assign col_center_o = col_center;
    assign row_center_o = row_center;
    assign w0_o = w0;
    assign w1_o = w1;
    assign w2_o = w2;

    assign bilinear_matrices_o = bilinear_matrices;

    assign confidence_o = confidence;
    assign depth_o = depth;
    assign depth_min_o = depth_min;
endmodule

// distributed under the mit license
// https://opensource.org/licenses/mit-license.php

`default_nettype none

module async_fifo

    #(
        parameter DSIZE = 8,
        parameter ASIZE = 4,
        parameter FALLTHROUGH = "TRUE" // First word fall-through without latency
    )(
        input  wire             wclk,
        input  wire             wrst_n,
        input  wire             winc,
        input  wire [DSIZE-1:0] wdata,
        output wire             wfull,
        output wire             awfull,
        input  wire             rclk,
        input  wire             rrst_n,
        input  wire             rinc,
        output wire [DSIZE-1:0] rdata,
        output wire             rempty,
        output wire             arempty
    );

    wire [ASIZE-1:0] waddr, raddr;
    wire [ASIZE  :0] wptr, rptr, wq2_rptr, rq2_wptr;

    // The module synchronizing the read point
    // from read to write domain
    sync_r2w
    #(ASIZE)
    sync_r2w (
    .wq2_rptr (wq2_rptr),
    .rptr     (rptr),
    .wclk     (wclk),
    .wrst_n   (wrst_n)
    );

    // The module synchronizing the write point
    // from write to read domain
    sync_w2r
    #(ASIZE)
    sync_w2r (
    .rq2_wptr (rq2_wptr),
    .wptr     (wptr),
    .rclk     (rclk),
    .rrst_n   (rrst_n)
    );

    // The module handling the write requests
    wptr_full
    #(ASIZE)
    wptr_full (
    .awfull   (awfull),
    .wfull    (wfull),
    .waddr    (waddr),
    .wptr     (wptr),
    .wq2_rptr (wq2_rptr),
    .winc     (winc),
    .wclk     (wclk),
    .wrst_n   (wrst_n)
    );

    // The DC-RAM
    fifomem
    #(DSIZE, ASIZE, FALLTHROUGH)
    fifomem (
    .rclken (rinc),
    .rclk   (rclk),
    .rdata  (rdata),
    .wdata  (wdata),
    .waddr  (waddr),
    .raddr  (raddr),
    .wclken (winc),
    .wfull  (wfull),
    .wclk   (wclk)
    );

    // The module handling read requests
    rptr_empty
    #(ASIZE)
    rptr_empty (
    .arempty  (arempty),
    .rempty   (rempty),
    .raddr    (raddr),
    .rptr     (rptr),
    .rq2_wptr (rq2_wptr),
    .rinc     (rinc),
    .rclk     (rclk),
    .rrst_n   (rrst_n)
    );

endmodule

`resetall

`default_nettype none

module sync_r2w

    #(
    parameter ASIZE = 4
    )(
    input  wire              wclk,
    input  wire              wrst_n,
    input  wire [ASIZE:0] rptr,
    output reg  [ASIZE:0] wq2_rptr
    );

    reg [ASIZE:0] wq1_rptr;

    always @(posedge wclk or negedge wrst_n) begin

        if (!wrst_n)
            {wq2_rptr,wq1_rptr} <= 0;
        else
            {wq2_rptr,wq1_rptr} <= {wq1_rptr,rptr};

    end

endmodule

`resetall

`default_nettype none

module sync_w2r

    #(
    parameter ASIZE = 4
    )(
    input  wire              rclk,
    input  wire              rrst_n,
    output reg  [ASIZE:0] rq2_wptr,
    input  wire [ASIZE:0] wptr
    );

    reg [ASIZE:0] rq1_wptr;

    always @(posedge rclk or negedge rrst_n) begin

        if (!rrst_n)
            {rq2_wptr,rq1_wptr} <= 0;
        else
            {rq2_wptr,rq1_wptr} <= {rq1_wptr,wptr};

    end

endmodule

`resetall

`default_nettype none

module wptr_full

	#(
		parameter ADDRSIZE = 4
	)(
		input  wire                wclk,
		input  wire                wrst_n,
		input  wire                winc,
		input  wire [ADDRSIZE  :0] wq2_rptr,
		output reg                 wfull,
		output reg                 awfull,
		output wire [ADDRSIZE-1:0] waddr,
		output reg  [ADDRSIZE  :0] wptr
	);

    reg  [ADDRSIZE:0] wbin;
    wire [ADDRSIZE:0] wgraynext, wbinnext, wgraynextp1;
    wire              awfull_val, wfull_val;

	// GRAYSTYLE2 pointer
	always @(posedge wclk or negedge wrst_n) begin

		if (!wrst_n)
			{wbin, wptr} <= 0;
		else
			{wbin, wptr} <= {wbinnext, wgraynext};

	end

    // Memory write-address pointer (okay to use binary to address memory)
    assign waddr = wbin[ADDRSIZE-1:0];
    assign wbinnext  = wbin + (winc & ~wfull);
    assign wgraynext = (wbinnext >> 1) ^ wbinnext;
    assign wgraynextp1 = ((wbinnext + 1'b1) >> 1) ^ (wbinnext + 1'b1);

    //------------------------------------------------------------------
    // Simplified version of the three necessary full-tests:
    // assign wfull_val=((wgnext[ADDRSIZE] !=wq2_rptr[ADDRSIZE] ) &&
    //                   (wgnext[ADDRSIZE-1]  !=wq2_rptr[ADDRSIZE-1]) &&
    // (wgnext[ADDRSIZE-2:0]==wq2_rptr[ADDRSIZE-2:0]));
    //------------------------------------------------------------------

     assign wfull_val = (wgraynext == {~wq2_rptr[ADDRSIZE:ADDRSIZE-1],wq2_rptr[ADDRSIZE-2:0]});
     assign awfull_val = (wgraynextp1 == {~wq2_rptr[ADDRSIZE:ADDRSIZE-1],wq2_rptr[ADDRSIZE-2:0]});

     always @(posedge wclk or negedge wrst_n) begin

        if (!wrst_n) begin
            awfull <= 1'b0;
            wfull  <= 1'b0;
        end else begin
            awfull <= awfull_val;
            wfull  <= wfull_val;
        end
    end

endmodule

`resetall

`default_nettype none

module fifomem

    #(
        parameter  DATASIZE = 8,    // Memory data word width
        parameter  ADDRSIZE = 4,    // Number of mem address bits
        parameter  FALLTHROUGH = "TRUE" // First word fall-through
    ) (
        input  wire                wclk,
        input  wire                wclken,
        input  wire [ADDRSIZE-1:0] waddr,
        input  wire [DATASIZE-1:0] wdata,
        input  wire                wfull,
        input  wire                rclk,
        input  wire                rclken,
        input  wire [ADDRSIZE-1:0] raddr,
        output wire [DATASIZE-1:0] rdata
    );

    localparam DEPTH = 1<<ADDRSIZE;

    reg [DATASIZE-1:0] mem [0:DEPTH-1];
    reg [DATASIZE-1:0] rdata_r;

    always @(posedge wclk) begin
        if (wclken && !wfull)
            mem[waddr] <= wdata;
    end

    generate
        if (FALLTHROUGH == "TRUE")
        begin : fallthrough
            assign rdata = mem[raddr];
        end
        else
        begin : registered_read
            always @(posedge rclk) begin
                if (rclken)
                    rdata_r <= mem[raddr];
            end
            assign rdata = rdata_r;
        end
    endgenerate

endmodule

`resetall

`default_nettype none

module rptr_empty

    #(
    parameter ADDRSIZE = 4
    )(
    input  wire                rclk,
    input  wire                rrst_n,
    input  wire                rinc,
    input  wire [ADDRSIZE  :0] rq2_wptr,
    output reg                 rempty,
    output reg                 arempty,
    output wire [ADDRSIZE-1:0] raddr,
    output reg  [ADDRSIZE  :0] rptr
    );

    reg  [ADDRSIZE:0] rbin;
    wire [ADDRSIZE:0] rgraynext, rbinnext, rgraynextm1;
    wire              arempty_val, rempty_val;

    //-------------------
    // GRAYSTYLE2 pointer
    //-------------------
    always @(posedge rclk or negedge rrst_n) begin

        if (!rrst_n)
            {rbin, rptr} <= 0;
        else
            {rbin, rptr} <= {rbinnext, rgraynext};

    end

    // Memory read-address pointer (okay to use binary to address memory)
    assign raddr     = rbin[ADDRSIZE-1:0];
    assign rbinnext  = rbin + (rinc & ~rempty);
    assign rgraynext = (rbinnext >> 1) ^ rbinnext;
    assign rgraynextm1 = ((rbinnext + 1'b1) >> 1) ^ (rbinnext + 1'b1);

    //---------------------------------------------------------------
    // FIFO empty when the next rptr == synchronized wptr or on reset
    //---------------------------------------------------------------
    assign rempty_val = (rgraynext == rq2_wptr);
    assign arempty_val = (rgraynextm1 == rq2_wptr);

    always @ (posedge rclk or negedge rrst_n) begin

        if (!rrst_n) begin
            arempty <= 1'b0;
            rempty <= 1'b1;
        end
        else begin
            arempty <= arempty_val;
            rempty <= rempty_val;
        end

    end

endmodule

`resetall

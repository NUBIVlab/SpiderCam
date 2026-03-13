class ConvolutionFloatingPoint #(
    parameter EXP_WIDTH  = 0,
    parameter FRAC_WIDTH = 0,

    parameter WINDOW_WIDTH  = 0,
    parameter WINDOW_HEIGHT = 0,

    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter FP_WIDTH_REG = 1 + EXP_WIDTH + FRAC_WIDTH
);
    Image #(FP_WIDTH_REG, WINDOW_WIDTH, WINDOW_HEIGHT) window;
    Image #(FP_WIDTH_REG, WINDOW_WIDTH, WINDOW_HEIGHT) kernel;
    logic [15:0] col;
    logic [15:0] row;
    int width;
    int height;
    logic [FP_WIDTH_REG - 1 : 0] convolved;

    function new();
        this.window = new();
        this.kernel = new();
        this.width  = WINDOW_WIDTH;
        this.height = WINDOW_HEIGHT;
    endfunction

    function void generate_random();
        for(int r = 0; r < WINDOW_HEIGHT; r++) begin
            for(int c = 0; c < WINDOW_WIDTH; c++) begin
                window.image[r][c] = $urandom;
                kernel.image[r][c] = $urandom;
            end
        end
        col = $urandom;
        row = $urandom;
    endfunction

    function void convolve_32();
        shortreal acc;
        shortreal w;
        shortreal k;
        acc = 0.0;
        for(int r = 0; r < WINDOW_HEIGHT; r++) begin
            for(int c = 0; c < WINDOW_WIDTH; c++) begin
                w = $bitstoshortreal(window.image[r][c]);
                k = $bitstoshortreal(kernel.image[r][c]);
                acc += (w * k);
            end
        end
        convolved = $shortrealtobits(acc);
    endfunction

    function void print_32();
        $display("-- Window --");
        window.print_32();
        $display("-- Kernel --");
        kernel.print_32();
        $display("Row %d, Col %d", row, col);
        $display();
    endfunction

endclass
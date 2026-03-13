import utilities_pkg::*;

class ConvolutionFloatingPointDriver #(type T, type I);

    TriggerableQueue #(T) in_queue;
    I inf;

    function new(
        TriggerableQueue #(T) in_queue,
        I inf
    );
        this.in_queue = in_queue;
        this.inf = inf;
    endfunction

    task automatic drive_convolution_floating_point(T convolution_floating_point);
        logic [1:0] rand_delay = 0;
        
        inf.window_i <= convolution_floating_point.window.image;
        inf.kernel_i <= convolution_floating_point.kernel.image;
        inf.col_i    <= convolution_floating_point.col;
        inf.row_i    <= convolution_floating_point.row;
        inf.valid_i  <= 1;
        @(posedge inf.clk_i);
        inf.valid_i <= 0;
        rand_delay = $urandom;
        repeat(rand_delay) @(posedge inf.clk_i);
        
    endtask;

    task automatic invalidate();
        inf.valid_i <= 0;
    endtask;

    task automatic run();
        T convolution_floating_point;
        invalidate();
        forever begin
            in_queue.pop(convolution_floating_point);
            drive_convolution_floating_point(convolution_floating_point);
            invalidate();
        end
    endtask

endclass
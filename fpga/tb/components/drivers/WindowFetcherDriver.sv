import utilities_pkg::*;

class WindowFetcherDriver #(type T_image, type I);

    TriggerableQueue #(T_image) in_queue;
    I inf;

    function new(
        TriggerableQueue #(T_image) in_queue,
        I inf
    );
        this.in_queue = in_queue;
        this.inf = inf;
    endfunction

    task automatic drive_image(T_image image);
        logic [1:0] rand_delay = 0;
        for(int r = 0; r < image.height; r++) begin
            for(int c = 0; c < image.width; c++) begin
                inf.data_i  <= image.image[r][c];
                inf.col_i   <= c;
                inf.row_i   <= r;
                inf.valid_i <= 1;
                @(posedge inf.clk_i);
                inf.valid_i <= 0;
                rand_delay = $urandom;
                repeat(rand_delay) @(posedge inf.clk_i);
            end
        end
    endtask;

    task automatic invalidate();
        inf.valid_i <= 0;
    endtask;

    task automatic run();
        int inter_image_delay = 7;
        T_image image;
        invalidate();
        forever begin
            in_queue.pop(image);
            drive_image(image);
            invalidate();
            repeat(inter_image_delay) @(posedge inf.clk_i);
        end
    endtask
endclass
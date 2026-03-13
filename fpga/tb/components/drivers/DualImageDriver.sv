import utilities_pkg::*;

class DualImageDriver #(type T_0, type T_1, type I);

    TriggerableQueue #(T_0) in_queue_0;
    TriggerableQueue #(T_1) in_queue_1;
    I inf;

    function new(
        TriggerableQueue #(T_0) in_queue_0,
        TriggerableQueue #(T_1) in_queue_1,
        I inf
    );
        this.in_queue_0 = in_queue_0;
        this.in_queue_1 = in_queue_1;
        this.inf = inf;
    endfunction

    task automatic drive_dual_images(T_0 img_0, T_1 img_1);
        logic [1:0] rand_delay = 0;
        for(int y = 0; y < img_0.height; y++) begin
            for(int x = 0; x < img_0.width; x++) begin
                inf.i_rho_plus_uint8_i  <= img_0.image[y][x];
                inf.i_rho_minus_uint8_i <= img_1.image[y][x];

                inf.col_i <= x;
                inf.row_i <= y;

                inf.valid_i <= 1;
                @(posedge inf.clk_i);
                inf.valid_i <= 0;
                //rand_delay = $urandom;
                repeat(rand_delay) @(posedge inf.clk_i);
            end
        end

    endtask;

    task automatic invalidate();
        inf.valid_i <= 0;
    endtask;

    task automatic run();
        T_0 img_0;
        T_1 img_1;
        invalidate();

        forever begin
            in_queue_0.pop(img_0);
            in_queue_1.pop(img_1);
            drive_dual_images(img_0, img_1);
            invalidate();
        end
    endtask
endclass
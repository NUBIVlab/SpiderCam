import utilities_pkg::*;

class WindowFetcherMonitor #(type T_window, type I);
    TriggerableQueueBroadcaster #(T_window) out_broadcaster;
    I inf;

    function new(TriggerableQueueBroadcaster #(T_window) out_broadcaster,
                 I inf);
        this.out_broadcaster = out_broadcaster;
        this.inf = inf;
    endfunction

    task automatic run();
        T_window window;
        forever begin
            @(negedge inf.clk_i);
            if(inf.valid_o) begin
                window = new();
                window.col_center = inf.col_o;
                window.row_center = inf.row_o;
                window.image = inf.window_o;
                out_broadcaster.push(window);
            end
        end
    endtask

endclass
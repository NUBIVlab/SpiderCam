import utilities_pkg::*;

class ConvolutionFloatingPointMonitor #(type T, type I);
    TriggerableQueueBroadcaster #(T) out_broadcaster;
    I inf;

    function new(TriggerableQueueBroadcaster #(T) out_broadcaster,
                 I inf);
        this.out_broadcaster = out_broadcaster;
        this.inf = inf;
    endfunction

    task automatic run();
        T convolution_floating_point;
        forever begin
            @(negedge inf.clk_i);
            if(inf.valid_o) begin
                convolution_floating_point = new();
                convolution_floating_point.convolved = inf.data_o;
                convolution_floating_point.col       = inf.col_o;
                convolution_floating_point.row       = inf.row_o;
                out_broadcaster.push(convolution_floating_point);
            end
        end
    endtask

endclass

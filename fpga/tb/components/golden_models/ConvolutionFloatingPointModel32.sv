import utilities_pkg::*;

class ConvolutionFloatingPointModel32 #(type T);
    TriggerableQueue #(T)  in_queue;
    TriggerableQueueBroadcaster #(T) out_broadcaster;

    function new(
        TriggerableQueue #(T)  in_queue,
        TriggerableQueueBroadcaster #(T) out_broadcaster
    );
        this.in_queue = in_queue;
        this.out_broadcaster = out_broadcaster;
    endfunction

    task automatic run();
        T convolution_floating_point;
        forever begin
            in_queue.pop(convolution_floating_point);
            convolution_floating_point.convolve_32();
            out_broadcaster.push(convolution_floating_point);
        end
    endtask
endclass 
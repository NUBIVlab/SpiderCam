import utilities_pkg::*;

class FpModel32 #(type T, parameter OP = 0);
    localparam FP_WIDTH_REG = 32;
    TriggerableQueue #(T) in_queue;
    TriggerableQueueBroadcaster #(T) out_broadcaster;

    function new(
        TriggerableQueue #(T) in_queue,
        TriggerableQueueBroadcaster #(T) out_broadcaster
    );
        this.in_queue = in_queue;
        this.out_broadcaster = out_broadcaster;
    endfunction

    task automatic run();
        T floating_points;
        shortreal a;
        shortreal b;
        shortreal r;
        logic [FP_WIDTH_REG - 1 : 0] a_bits;
        logic [FP_WIDTH_REG - 1 : 0] b_bits;
        logic [FP_WIDTH_REG - 1 : 0] r_bits;

        forever begin
            in_queue.pop(floating_points);
            a = $bitstoshortreal(floating_points.a);
            b = $bitstoshortreal(floating_points.b);
            if(OP == 0) begin
                r = a + b;
            end else if (OP == 1) begin
                r = a * b;
            end else if (OP == 2) begin
                r = a / b;
            end
            a_bits = $shortrealtobits(a);
            b_bits = $shortrealtobits(b);
            r_bits = $shortrealtobits(r);
            floating_points = new(a_bits,b_bits,r_bits);
            out_broadcaster.push(floating_points);
        end
    endtask
endclass
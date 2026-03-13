import utilities_pkg::*;

class FpScoreboard32 #(type T);
    TriggerableQueue #(T) in_queue_dut;
    TriggerableQueue #(T) in_queue_golden;

    function new(
        TriggerableQueue #(T) in_queue_dut,
        TriggerableQueue #(T) in_queue_golden
    );
        this.in_queue_dut = in_queue_dut;
        this.in_queue_golden = in_queue_golden;
    endfunction

    task automatic run();
        T floating_points_dut;
        T floating_points_golden;
        int received = 0;
        // 256*256*2*2*1
        int expecting = 255*255*2*2*80;

        int correct = 0;
        int off_by_one = 0;
        int nan_correct = 0;
        int subnormal_correct = 0;
        int underflow_correct = 0;
        int overflow_correct = 0;
        int error = 0;

        forever begin
            in_queue_dut.pop(floating_points_dut);
            in_queue_golden.pop(floating_points_golden);
            if(floating_points_golden.r == floating_points_dut.r) begin
                /*
                $display("Pass expected: %h got %h", floating_points_golden.r, floating_points_dut.r);
                $display("A, B: %h %h",floating_points_golden.a, floating_points_golden.b);
                $display($bitstoshortreal(floating_points_golden.a));
                $display($bitstoshortreal(floating_points_golden.b));
                $display($bitstoshortreal(floating_points_golden.r));
                $display($bitstoshortreal(floating_points_dut.r));
                */
                correct++;
            end else begin
                if((floating_points_dut.r[30:23] == 255) && (floating_points_golden.r[30:23] == 255)) begin
                    nan_correct++;
                end else if((floating_points_dut.r[30:23] == 0) && (floating_points_golden.r[30:23] == 0)) begin
                    subnormal_correct++;
                end else if((floating_points_dut.r[30:23] == 0) && (floating_points_golden.r[30:23] == 1)) begin
                    underflow_correct++;
                end else if((floating_points_dut.r[30:23] == 254) && (floating_points_golden.r[30:23] == 255)) begin
                    overflow_correct++;
                end else if(((floating_points_dut.r - floating_points_golden.r) == 1) ||
                            ((floating_points_dut.r - floating_points_golden.r) == -1)) begin
                    /*
                    $display("Pass expected: %h got %h", floating_points_golden.r, floating_points_dut.r);
                    $display("A, B: %h %h",floating_points_golden.a, floating_points_golden.b);
                    $display($bitstoshortreal(floating_points_golden.a));
                    $display($bitstoshortreal(floating_points_golden.b));
                    $display($bitstoshortreal(floating_points_golden.r));
                    $display($bitstoshortreal(floating_points_dut.r));
                    */
                    off_by_one++;
                end  else begin
                    $display("Error expected: %h got %h", floating_points_golden.r, floating_points_dut.r);
                    $display("A, B: %h %h",floating_points_golden.a, floating_points_golden.b);
                    $display($bitstoshortreal(floating_points_golden.a));
                    $display($bitstoshortreal(floating_points_golden.b));
                    $display($bitstoshortreal(floating_points_golden.r));
                    $display($bitstoshortreal(floating_points_dut.r));
                    
                    error++;
                end
            end
            received++;
            if(received >= expecting) begin
                $display("Fininshed");
                $display("Perfect: %d", correct);
                $display("Off by one: %d", off_by_one);
                $display("NaN result: %d", nan_correct);
                $display("Subnormal result: %d", subnormal_correct);
                $display("Intermediate underflow: %d", underflow_correct);
                $display("Intermediate overflow: %d", overflow_correct);
                $display("Genuine error: %d", error);
                $display("Total samples: %d", received);
                $finish;
            end
        end

    endtask
endclass
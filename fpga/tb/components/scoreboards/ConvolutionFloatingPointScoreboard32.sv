import utilities_pkg::*;

class ConvolutionFloatingPointScoreboard32 #(type T);
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
        T convolution_floating_point_dut;
        T convolution_floating_point_golden;
        int received = 0;
        int expecting = 100;
        shortreal dut;
        shortreal golden;
        int same = 0;
        int nan_inf_correct = 0;
        int subnormal_correct = 0;

        forever begin
            in_queue_dut.pop(convolution_floating_point_dut);
            in_queue_golden.pop(convolution_floating_point_golden);

            if(convolution_floating_point_dut.convolved != convolution_floating_point_golden.convolved) begin
                dut = $bitstoshortreal(convolution_floating_point_dut.convolved);
                golden = $bitstoshortreal(convolution_floating_point_golden.convolved);
                //convolution_floating_point_golden.print_32();
                if(convolution_floating_point_golden.convolved[30:23] == 255) begin
                    nan_inf_correct++;
                end else if((convolution_floating_point_golden.convolved[30:23] == 0) &&
                            (convolution_floating_point_dut.convolved[30:23] == 0)) begin
                    subnormal_correct++;
                end else begin
                    //$display("Mismatch difference is %0.4f", (golden - dut));
                    //$display(golden);
                    //$display(dut);
                end
                
            end else begin
                same++;
            end

            received++;

            if(received >= expecting) begin
                $display("Same Values found: ");
                $display(same);
                $display("NaN or Infinity From Golden: ");
                $display(nan_inf_correct);
                $display("Subnormal approximations:");
                $display(subnormal_correct);
                $display("Total Samples - %d", expecting);
                $display("finished");
                $finish();
            end
            
        end
    endtask

    
endclass
import utilities_pkg::*;

class ConvolutionFloatingPointGenerator #(type T);
    TriggerableQueueBroadcaster #(T) out_broadcaster;

    function new(TriggerableQueueBroadcaster #(T) out_broadcaster);
        this.out_broadcaster = out_broadcaster;
    endfunction

    task automatic run();
        T ConvolutionFloatingPoint;

        for(int i = 0; i < 100; i++) begin
            ConvolutionFloatingPoint = new();
            ConvolutionFloatingPoint.generate_random();

            /*
            // ? x ? - ?
            ConvolutionFloatingPoint.kernel.image[0][0] = ?;
            ConvolutionFloatingPoint.kernel.image[0][1] = ?;
            ConvolutionFloatingPoint.kernel.image[0][2] = ?;
            ConvolutionFloatingPoint.kernel.image[1][0] = ?;
            ConvolutionFloatingPoint.kernel.image[1][1] = ?;
            ConvolutionFloatingPoint.kernel.image[1][2] = ?;
            ConvolutionFloatingPoint.kernel.image[2][0] = ?;
            ConvolutionFloatingPoint.kernel.image[2][1] = ?;
            ConvolutionFloatingPoint.kernel.image[2][2] = ?;
            */

            // 3 x 3 - stress test
            ConvolutionFloatingPoint.kernel.image[0][0] = 0;
            ConvolutionFloatingPoint.kernel.image[0][1] = 0;
            ConvolutionFloatingPoint.kernel.image[0][2] = 32'h40a00000;
            ConvolutionFloatingPoint.kernel.image[1][0] = 32'hc1000000;
            ConvolutionFloatingPoint.kernel.image[1][1] = 32'h3f800000;
            ConvolutionFloatingPoint.kernel.image[1][2] = 32'h40400000;
            ConvolutionFloatingPoint.kernel.image[2][0] = 0;
            ConvolutionFloatingPoint.kernel.image[2][1] = 32'h40e00000;
            ConvolutionFloatingPoint.kernel.image[2][2] = 32'h3d800000;
            

            //ConvolutionFloatingPoint.print_32();
            out_broadcaster.push(ConvolutionFloatingPoint);
        end

        $display("All values generated.");
    endtask
endclass
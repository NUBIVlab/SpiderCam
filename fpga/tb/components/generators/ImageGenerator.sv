import utilities_pkg::*;

class ImageGenerator #(type T);
    TriggerableQueueBroadcaster #(T) out_broadcaster;
    logic [15:0] col_center;
    logic [15:0] row_center;

    function new(TriggerableQueueBroadcaster #(T) out_broadcaster);
        this.out_broadcaster = out_broadcaster;
    endfunction
    
    task automatic run();
        T image;
        
        for(int i = 0; i < 4; i++) begin
            image = new();
            image.generate_random_image();
            image.col_center = this.col_center;
            image.row_center = this.row_center; 
            image.print();
            out_broadcaster.push(image);
        end
        
        $display("All values generated.");
        
        out_broadcaster.push(image);
        
    endtask
endclass
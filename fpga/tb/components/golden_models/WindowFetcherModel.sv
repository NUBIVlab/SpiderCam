import utilities_pkg::*;

class WindowFetcherModel #(type T_image, type T_window, parameter BORDER_ENABLE = 0, parameter BORDER_EXTENSION_CONSTANT = 0);
    TriggerableQueue #(T_image)  in_queue;
    TriggerableQueueBroadcaster #(T_window) out_broadcaster;

    function new(
        TriggerableQueue #(T_image)  in_queue,
        TriggerableQueueBroadcaster #(T_window) out_broadcaster
    );
        this.in_queue = in_queue;
        this.out_broadcaster = out_broadcaster;
    endfunction

    task automatic run();
        T_image image;
        T_window window;
        forever begin
            in_queue.pop(image);
            for(int r_image = 0; r_image < image.height; r_image++) begin
                for(int c_image = 0; c_image < image.width; c_image++) begin
                window = new();
                window.generate_constant_image(0);   
                    for(int r_window = 0; r_window < window.height; r_window++) begin
                        for(int c_window = 0; c_window < window.width; c_window++) begin
                            int c_center_dist = c_window - image.col_center;
                            int r_center_dist = r_window - image.row_center;
                            logic [15:0] c_img = c_image + c_center_dist; 
                            logic [15:0] r_img = r_image + r_center_dist;
                            if((r_img < 0) || (r_img > (image.height - 1)) || (c_img < 0) || (c_img > (image.width - 1))) begin
                                if(BORDER_ENABLE) window.image[r_window][c_window] = BORDER_EXTENSION_CONSTANT;
                            end else begin
                                window.image[r_window][c_window] = image.image[r_img][c_img];
                            end 
                        end
                    end
                window.col_center = c_image;
                window.row_center = r_image;
                out_broadcaster.push(window);
                end
            end

        end
    endtask
endclass 

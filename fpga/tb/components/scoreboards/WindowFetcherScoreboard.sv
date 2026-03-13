import utilities_pkg::*;

class WindowFetcherScoreboard #(type T_window, parameter BORDER_ENABLE = 0, parameter BORDER_EXTENSION_CONSTANT = 0);
    TriggerableQueue #(T_window) in_queue_dut;
    TriggerableQueue #(T_window) in_queue_golden;

    function new(
        TriggerableQueue #(T_window) in_queue_dut,
        TriggerableQueue #(T_window) in_queue_golden
    );
        this.in_queue_dut = in_queue_dut;
        this.in_queue_golden = in_queue_golden;
    endfunction

    task automatic run();
        T_window window_dut;
        T_window window_golden;
        int received = 0;
        // 10x7 image
        int expecting = 50;

        forever begin
            in_queue_dut.pop(window_dut);
            in_queue_golden.pop(window_golden);
            if(BORDER_ENABLE) begin
                if(window_dut.image != window_golden.image) begin
                    $display("Window values do not match:");
                    $display("#%d", received);
                    window_golden.print();
                    window_dut.print();
                end
                
                else begin
                    $display("Window values match:");
                    $display("#%d", received);
                    window_golden.print();
                    window_dut.print();
                end
                
            end else begin
                if(!compare_no_border(window_dut, window_golden)) begin
                    $display("Window values do not match:");
                    $display("#%d", received);
                    window_golden.print();
                    window_dut.print();
                end 
                
                else begin
                    $display("Window values match:");
                    $display("#%d", received);
                    window_golden.print();
                    window_dut.print();
                end
                
            end
            if((window_dut.col_center != window_golden.col_center) || 
                (window_dut.row_center != window_golden.row_center)) begin
                    $display("Row and Col doesn't match:");
                    $display("(%d, %d)", window_golden.row_center, window_golden.col_center);
                    $display("(%d, %d)", window_dut.row_center, window_dut.col_center);
            end

            received++;
            if(received >= expecting) begin
                $display("finished");
                $finish();
            end
        end
    endtask

    function bit compare_no_border(T_window window_dut, T_window window_golden);
        bit e = 1;
        for(int r = 0; r < window_dut.height; r++) begin
            for(int c = 0; c < window_dut.width; c++) begin
                if((window_dut.image[r][c] != window_golden.image[r][c]) && (window_golden.image[r][c] != 0)) begin
                    e = 0;
                    return e;
                end
            end
        end
        return e;

    endfunction;
    
endclass
import utilities_pkg::*;

class FpGenerator32 #(type T);
    localparam FP_WIDTH_REG = 32;
    localparam FP_EXP_WIDTH = 8;
    localparam FP_FRAC_WIDTH = 23;
    TriggerableQueueBroadcaster #(T) out_broadcaster;

    function new(TriggerableQueueBroadcaster #(T) out_broadcaster);
        this.out_broadcaster = out_broadcaster;
    endfunction
    
    task automatic run();
        T points;
        logic [FP_WIDTH_REG - 1 : 0] a;
        logic [FP_EXP_WIDTH - 1 : 0] a_exp;
        logic [FP_FRAC_WIDTH - 1 : 0] a_frac;

        logic [FP_WIDTH_REG - 1 : 0] b;
        logic [FP_EXP_WIDTH - 1 : 0] b_exp;
        logic [FP_FRAC_WIDTH - 1 : 0] b_frac;

        logic [FP_WIDTH_REG - 1 : 0] r = 0;
        
        for(int i = 0; i < 80; i++) begin
            for(int e_a = 1; e_a < (2**FP_EXP_WIDTH); e_a++) begin
                for(int e_b = 1; e_b < (2**FP_EXP_WIDTH); e_b++) begin
                    for(int s_a = 0; s_a < 2; s_a++) begin
                        for(int s_b = 0; s_b < 2; s_b++) begin
                            a_exp = e_a[FP_EXP_WIDTH - 1 : 0];
                            a_frac = $urandom;
                            a = {{s_a[0]}, a_exp, a_frac};
                            b_exp = e_b[FP_EXP_WIDTH - 1 : 0];
                            b_frac = $urandom;
                            b = {{s_b[0]}, b_exp, b_frac};
                            points = new(a, b, r);
                            out_broadcaster.push(points);
                        end
                    end
                end
            end
        end
        $display("All values generated.");
        
        
        a = 32'hc3980000;
        b = 32'h89f4a330;
        r = 0;
        points = new(a, b, r);
        out_broadcaster.push(points);
        
    endtask
endclass
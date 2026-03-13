function bit greater_than_fp16(logic unsigned [15:0] fp_a, logic unsigned [15:0] fp_b)
    logic       fp_a_sign;
    logic       fp_b_sign;

    fp_a_sign = fp_a[15];
    fp_b_sign = fp_b[15];

    if((!fp_a_sign) && (!fp_b_sign)) begin
        return (fp_a > fp_b);
    end else if ((!fp_a_sign) && fp_b_sign) begin
        return 1;
    end else if (fp_a_sign && (!fp_b_sign)) begin
        return 0;
    end else begin
        return (fp_a < fp_b);
    end
endfunction

function bit greater_than_absolute_fp16(logic unsigned [15:0] fp_a, logic unsigned [15:0] fp_b)
    return (fp_a > fp_b)
endfunction
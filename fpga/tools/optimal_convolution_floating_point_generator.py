"""
 * MSB      | LSB      | meaning 
 * ---------------------------------
 * 0x00..0  | 0x00..0  | multiply by 0
 * 0x00..1  | 0x??..?  | multiply by + 2**(??)
 * 0x00..2  | 0x??..?  | multiply by - 2**(??)
 * 0xff..f  | 0xff..f  | no optimization
 *
 * LSB is treated as signed and has the width of EXP_WIDTH.
 * For simplicity, the MSB also has the width EXP_WIDTH.
 *
 * Features an OPTIMAL_ADD parameter, which unfortunately, we have to
 * optimize at each level of the adder tree manually.
 * 0 - means there is nothing to add
 * 1 - means there is something to add

--------------------------------------------------------------------------------------------
LINEAR_WIDTH        = WINDOW_WIDTH * WINDOW_HEIGHT
LINEAR_WIDTH_2CLOG2 = 2 ** $clog2(LINEAR_WIDTH)
OPTIMAL_ADD_LEVELS  = $clog2(LINEAR_WIDTH_2CLOG2)

[0:0] OPTIMAL_ADD  [OPTIMAL_ADD_LEVELS][LINEAR_WIDTH_CLOG2] = {default:1} // everything starts as having 1

// 0th level
for(genvar l = 0; l < 0; l++) begin
    for(opt = 0; opt < LINEAR_WIDTH; opt++) begin
        if(OPTIMAL_MULT[opt] == 0) OPTIMAL_ADD[opt] = 0;
    end
    for(opt = LINEAR_WIDTH; opt < LINEAR_WIDTH_2CLOG2; opt++) begin
        OPTIMAL_ADD[opt] = 0;
    end
end

// rest of levels
for(l = 1; l < OPTIMAL_ADD_LEVELS; l++) begin
    for(opt = 0; opt < (2**(OPTIMAL_ADD_LEVELS - l)); opt++) begin
        l_up  = l - 1;
        idx_0 = opt * 2;
        idx_1 = opt * 2 + 1;
        if((optimal_add[l_up][idx_0] == 0) && (optimal_add[l_up][idx_1] == 0)) begin
            OPTIMAL_ADD[l][opt] = 0
        end
    end
end
----------------------------------------------------------------------------------------------
"""
from math import  log2, ceil

def is_power_of_two(n):
    if n <= 0:
        return False
    
    if isinstance(n, int) or n.is_integer():
        n = int(n)
        return (n  & (n - 1)) == 0
    else:
        return log2(n).is_integer()

def int_to_signed_bin(n, width):
    if n >= 0:
        s = format(n, f'0{width}b')
    else:
        # Compute two's complement for negative number
        s = format((1 << width) + n, f'0{width}b')
    return s

def opt_mult_str(kernel_value, EXP_WIDTH, EXP_MAX):
    opt_mult_header = str(EXP_WIDTH * 2) + "'b"
    opt_mult_msb     = 0
    opt_mult_msb_str = ""
    opt_mult_lsb     = 0
    opt_mult_lsb_str = ""
    opt_mult_str     = ""

    # Is this 0
    if(kernel_value == 0):
        pass
    # Is this a power of 2
    elif(is_power_of_two(abs(kernel_value))):
        if(kernel_value < 0):
            opt_mult_msb = 2
        else:
            opt_mult_msb = 1
        opt_mult_lsb = int(log2(abs(kernel_value)))

    # else, no optimization here
    else:
        opt_mult_msb = EXP_MAX
        opt_mult_lsb = EXP_MAX

    opt_mult_msb_str = int_to_signed_bin(opt_mult_msb, EXP_WIDTH)
    opt_mult_lsb_str = int_to_signed_bin(opt_mult_lsb, EXP_WIDTH)
    opt_mult_str = opt_mult_header + opt_mult_msb_str + opt_mult_lsb_str

    return opt_mult_str


def generate_optimal_convolution_floating_point(EXP_WIDTH=0, FRAC_WIDTH=0, KERNEL=[[]], module_name="default_name"):
    WINDOW_HEIGHT = len(KERNEL)
    WINDOW_WIDTH  = len(KERNEL[0])
    
    KERNEL_2D = KERNEL
    KERNEL_2D_STR = ""
    for r in range(WINDOW_HEIGHT):
        KERNEL_2D_STR += (str(KERNEL_2D[r]) + "\n")

    # flatten KERNEL 
    KERNEL = [item for sublist in KERNEL for item in sublist]

    LINEAR_WIDTH        = WINDOW_WIDTH * WINDOW_HEIGHT
    LINEAR_WIDTH_2CLOG2 = 2 ** (ceil(log2(LINEAR_WIDTH)))
    OPT_DATA_WIDTH      = EXP_WIDTH * 2

    EXP_MAX        = 2 ** (EXP_WIDTH) - 1
    DOUBLE_EXP_MAX = 2 ** (OPT_DATA_WIDTH) - 1

    OPTIMAL_ADD_LEVELS = ceil(log2(LINEAR_WIDTH_2CLOG2))

    OPTIMAL_MULT_STR = "'{"
    OPTIMAL_ADD_STR  = "'{\n"

    OPTIMAL_ADD = [[1 for _ in range(LINEAR_WIDTH_2CLOG2)] for _ in range(OPTIMAL_ADD_LEVELS)]
    
    for opt in range(LINEAR_WIDTH, LINEAR_WIDTH_2CLOG2):
        OPTIMAL_ADD[0][opt] = 0

    for l in range(1, OPTIMAL_ADD_LEVELS):
        for opt in range(2**(OPTIMAL_ADD_LEVELS - l), LINEAR_WIDTH_2CLOG2):
            OPTIMAL_ADD[l][opt] = 0

    for opt in range(LINEAR_WIDTH):
        if((opt % WINDOW_WIDTH) == 0):
                OPTIMAL_MULT_STR += "\n"
        OPTIMAL_MULT_STR += (opt_mult_str(KERNEL[opt],EXP_WIDTH, EXP_MAX) + ",")
        if(KERNEL[opt] == 0):
            OPTIMAL_ADD[0][opt] = 0

    OPTIMAL_MULT_STR = OPTIMAL_MULT_STR[:-1]
    OPTIMAL_MULT_STR += "};"

    for l in range(1, OPTIMAL_ADD_LEVELS):
        l_up = l - 1
        for opt in range((2**(OPTIMAL_ADD_LEVELS - l))):
            idx_0 = opt * 2
            idx_1 = (opt * 2) + 1
            if((OPTIMAL_ADD[l_up][idx_0] == 0) and (OPTIMAL_ADD[l_up][idx_1] == 0)): 
                OPTIMAL_ADD[l][opt] = 0

    for l in range(OPTIMAL_ADD_LEVELS):
        OPTIMAL_ADD_STR += "'{"
        for opt in range(LINEAR_WIDTH_2CLOG2):
            if((l == 0) and (opt == LINEAR_WIDTH)):
                OPTIMAL_ADD_STR += "        "
            if(opt == (2**(OPTIMAL_ADD_LEVELS - l))):
                OPTIMAL_ADD_STR += "        "
            OPTIMAL_ADD_STR += (str(OPTIMAL_ADD[l][opt]) + ",")
            
        OPTIMAL_ADD_STR = OPTIMAL_ADD_STR[:-1]
        OPTIMAL_ADD_STR += "},\n"

    OPTIMAL_ADD_STR = OPTIMAL_ADD_STR[:-2]
    OPTIMAL_ADD_STR += "\n};"
  
    
    print("---------- OPTIMAL MULT --------")
    print(OPTIMAL_MULT_STR)
    print("---------- OPTIMAL ADDER TREE ---------")
    print(OPTIMAL_ADD_STR)
    print("----------")
    

    CODE = """/*
AUTOGEN CONVOLUTION_FLOATING_WRAPPER
-- KERNEL -- 
%s
*/

module %s #(
    parameter EXP_WIDTH = %s,
    parameter FRAC_WIDTH = %s,

    parameter WINDOW_WIDTH = %s,
    parameter WINDOW_HEIGHT = %s,

    ////////////////////////////////////////////////////////////////
    // Local parameters
    parameter FP_WIDTH_REG = 1 + FRAC_WIDTH + EXP_WIDTH,

    parameter LINEAR_WIDTH        = WINDOW_WIDTH * WINDOW_HEIGHT, 
    parameter LINEAR_WIDTH_2CLOG2 = 2 ** $clog2(LINEAR_WIDTH),     
    
    parameter OPT_DATA_WIDTH                           = EXP_WIDTH * 2,                     
    parameter EXP_MAX                                  = 2**EXP_WIDTH - 1,                  
    parameter [OPT_DATA_WIDTH - 1 : 0] DOUBLE_EXP_MAX  = 2**(EXP_WIDTH + EXP_WIDTH) - 1, 

    parameter OPTIMAL_ADD_LEVELS = $clog2(LINEAR_WIDTH_2CLOG2) 
) (
    input clk_i,
    input rst_i,

    input  [FP_WIDTH_REG - 1 : 0] window_i [WINDOW_HEIGHT][WINDOW_WIDTH],
    input  [FP_WIDTH_REG - 1 : 0] kernel_i [WINDOW_HEIGHT][WINDOW_WIDTH],
    input  [15:0]                 col_i,
    input  [15:0]                 row_i,
    input                         valid_i,

    output [FP_WIDTH_REG - 1 : 0] data_o,
    output [15:0]                 col_o,
    output [15:0]                 row_o,
    output                        valid_o
);
    localparam [OPT_DATA_WIDTH - 1 : 0] OPTIMAL_MULT [LINEAR_WIDTH] =
%s

    localparam [0:0] OPTIMAL_ADD  [OPTIMAL_ADD_LEVELS][LINEAR_WIDTH_2CLOG2] = 
%s

    convolution_floating_point #(
        .EXP_WIDTH(EXP_WIDTH),
        .FRAC_WIDTH(FRAC_WIDTH),

        .WINDOW_WIDTH(WINDOW_WIDTH),
        .WINDOW_HEIGHT(WINDOW_HEIGHT),

        .OPTIMAL_MULT(OPTIMAL_MULT),
        .OPTIMAL_ADD(OPTIMAL_ADD)
    ) inst (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .window_i(window_i),
        .kernel_i(kernel_i),
        .col_i(col_i),
        .row_i(row_i),
        .valid_i(valid_i),

        .data_o(data_o),
        .col_o(col_o),
        .row_o(row_o),
        .valid_o(valid_o)
    );

endmodule""" % (KERNEL_2D_STR, module_name, str(EXP_WIDTH), str(FRAC_WIDTH), str(WINDOW_WIDTH), str(WINDOW_HEIGHT), OPTIMAL_MULT_STR, OPTIMAL_ADD_STR)
    #print(CODE)
    
    with open(module_name + ".sv", "w") as f:
        f.write(CODE)
    f.close()
    print(module_name + ".sv" + " generated at current working directory.")


    return

if __name__ == "__main__":
    EXP_WIDTH = 5
    FRAC_WIDTH = 10
    KERNEL = [[1],
              [1],
              [1],
              [1],
              [1],
              [1],
              [1],
              [1],
              [1],
              [1],
              [1]]
    
    generate_optimal_convolution_floating_point(EXP_WIDTH, FRAC_WIDTH, KERNEL, "box_v_0_ones_11_fp16")


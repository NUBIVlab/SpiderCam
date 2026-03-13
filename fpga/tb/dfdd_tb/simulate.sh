export bindir="/usr/local/diamond/3.13/bin/lin64"
source /usr/local/diamond/3.13/bin/lin64/diamond_env

rm -rf simulate
mkdir simulate
cd simulate
vlib work

# Directories
TB_DIR="../../testbench"
CT_DIR="../../components"
RTL_DIR="../../../rtl"
TP_DIR="../../../rtl/third_party"
PJ_DIR="../../../projects"

# Include directory flags
INCLUDE_FLAGS="-incdir "$RTL_DIR" 
               -incdir "$TB_DIR" 
               -incdir "$TP_DIR" 
               -incdir "$CT_DIR"/drivers
               -incdir "$CT_DIR"/generators
               -incdir "$CT_DIR"/golden_models
               -incdir "$CT_DIR"/interfaces
               -incdir "$CT_DIR"/monitors
               -incdir "$CT_DIR"/package_manager
               -incdir "$CT_DIR"/scoreboards
               -incdir "$CT_DIR"/utilities
               -incdir "$PJ_DIR"/dfdd
               "

# Run vlog on all source files.
error_highlighter() {
    grep --color -e ".*Errors: [1-9].*" -e "^"
}


vlog $INCLUDE_FLAGS -sv ../dfdd_tb.sv | error_highlighter

export bindir=""

# -c argument gets name of testbench module.
vsim -c dfdd_tb -do "run -all; quit" | error_highlighter


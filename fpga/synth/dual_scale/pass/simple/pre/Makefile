PROJ=top
TRELLIS?=/usr/local/share/trellis

all: ${PROJ}.bit

%.json: top.sv
	yosys -s synth.yosys | tee yosys.log

%_out.config: %.json
	nextpnr-ecp5 --json $< --textcfg $@ --um5g-85k --package CABGA381 --lpf ecp5evn.lpf --seed 42 --log nextpnr.log
	

%.bit: %_out.config
	ecppack --svf ${PROJ}.svf $< $@

${PROJ}.svf : ${PROJ}.bit

prog: ${PROJ}.svf
	openocd -f ./ecp5-evn.cfg -c "transport select jtag; init; svf $<; exit"

clean:
	rm -f *.svf *.bit *.config *.json

.PHONY: all prog clean

.PHONY: test compile

export LIBPYTHON_LOC=$(shell cocotb-config --libpython)
export PYGPI_PYTHON_BIN=$(shell cocotb-config --python-bin)

test_%:
	make compile
	iverilog -o build/sim.vvp -s gpu -g2012 build/gpu.v
	COCOTB_TEST_MODULES=test.test_$* vvp -M $$(cocotb-config --lib-dir) -m libcocotbvpi_icarus build/sim.vvp +dumpfile=build/$*.vcd +dumpvars
	
compile:
	sv2v -I src -I src/core src/*.sv src/core/*.sv -w build/gpu.v
	echo '`timescale 1ns/1ns' > build/temp.v
	cat build/gpu.v >> build/temp.v
	mv build/temp.v build/gpu.v

# TODO: Get gtkwave visualizaiton
clean:
	rm -rf build/

clean_logs:
	rm -rf test/logs/

show_%: %.vcd %.gtkw
	gtkwave $^



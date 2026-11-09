# Systolic array accelerator - convenience targets
.PHONY: all compile sim wave wave-pe synth clean

all: sim

compile:
	./simulation/compile.sh

sim:
	./simulation/run_simulation.sh

wave:          ## full-system waveform with saved signal layout
	gtkwave simulation/waveforms/tb_top_module.vcd simulation/waveforms/top_overview.gtkw &

wave-pe:
	gtkwave simulation/waveforms/tb_top_module.vcd simulation/waveforms/pe_dataflow.gtkw &

synth:
	cd synthesis && ./run_synthesis.sh

clean:
	rm -rf simulation/build

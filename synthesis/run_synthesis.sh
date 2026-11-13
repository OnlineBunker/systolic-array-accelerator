#!/usr/bin/env bash
# Yosys synthesis. Two flows per design:
#   generic : technology-independent gates/cells (synth)
#   xc7     : mapped to Xilinx 7-series primitives (synth_xilinx) - pre-place-and-route estimate
set -u
cd "$(dirname "$0")"
for top in top_module sequential_matmul; do
  yosys -q -l yosys_${top}_generic.log -p "read_verilog ../rtl/*.v; synth -top ${top} -flatten; stat -width" > /dev/null
  yosys -q -l yosys_${top}_xc7.log     -p "read_verilog ../rtl/*.v; synth_xilinx -top ${top} -family xc7 -flatten; stat" > /dev/null
  echo "done: ${top}"
done

#!/usr/bin/env bash
# Compile every testbench with Icarus Verilog. Logs -> simulation/logs/
set -u
cd "$(dirname "$0")/.."
mkdir -p simulation/build simulation/logs
status=0
for tb in processing_element systolic_array top_module sequential_matmul; do
    echo ">>> iverilog -g2005 -Wall -s tb_${tb} rtl/*.v testbench/tb_${tb}.v"
    if iverilog -g2005 -Wall -s tb_${tb} -o simulation/build/tb_${tb}.vvp \
         rtl/*.v testbench/tb_${tb}.v > simulation/logs/compile_${tb}.log 2>&1; then
        echo "    OK  (warnings/errors: $(wc -l < simulation/logs/compile_${tb}.log) lines)"
    else
        echo "    FAILED - see simulation/logs/compile_${tb}.log"; cat simulation/logs/compile_${tb}.log; status=1
    fi
done
exit $status

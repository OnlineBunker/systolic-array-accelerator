#!/usr/bin/env bash
# Compile and run all testbenches. Logs -> simulation/logs/, VCD -> simulation/waveforms/
set -u
cd "$(dirname "$0")/.."
./simulation/compile.sh || exit 1
mkdir -p simulation/waveforms
fail=0
for tb in processing_element systolic_array top_module sequential_matmul; do
    echo
    echo ">>> vvp simulation/build/tb_${tb}.vvp"
    vvp -n simulation/build/tb_${tb}.vvp > simulation/logs/sim_${tb}.log 2>&1
    grep -E "TESTBENCH|BASELINE|latency start|Sustained" simulation/logs/sim_${tb}.log | sed 's/^/    /'
    grep -qE "(TESTBENCH|BASELINE).*-> PASS" simulation/logs/sim_${tb}.log || fail=1
done
echo
if [ $fail -eq 0 ]; then echo "ALL TESTBENCHES PASSED"; else echo "SOME TESTBENCHES FAILED"; fi
exit $fail

# Performance Analysis: 4×4 Systolic Array vs Sequential Matrix Multiplication

Every number in this document was measured by a tool run in this project.
The source log is named next to each figure. Nothing is estimated unless
it is explicitly labelled as derived arithmetic.

## 1. Designs compared

| | Systolic array (`top_module`) | Sequential baseline (`sequential_matmul`) |
|---|---|---|
| Processing elements | 16 PEs (4×4), one MAC each | 1 MAC unit |
| Operands | signed Q8.8, 16 bit | signed Q8.8, 16 bit |
| Accumulator | 34 bit per PE | 34 bit |
| MAC structure | 2-stage (multiply, then accumulate) | 1-stage |
| Host interface | identical: write A/B by address, `start`, `done`, read C by address | identical |

Both designs compute exactly the same function. Both pass their
self-checking testbenches against an independent reference model.

## 2. Methodology

**Cycle counts.** These come from simulation with Icarus Verilog 12.0.

* *Latency*: the number of rising clock edges from the edge that samples
  `start` until the first edge after which `done` = 1. It is counted
  inside `tb_top_module.v` and `tb_sequential_matmul.v` by the task
  `start_and_wait`.
* *Sustained period*: `start` is held high for six jobs. The testbench
  counts cycles between the 2nd and 6th completion and divides by 4.

Logs: `simulation/logs/sim_top_module.log`, `simulation/logs/sim_sequential_matmul.log`.

**Per-PE activity.** For every PE, the cycles in which its `acc_en_r`
signal is 1 during Test Case 2 were extracted from
`simulation/waveforms/tb_top_module.vcd`.
Output: `project_artifacts/diagrams/execution_timing_from_vcd.png`.

**FPGA resources and Fmax.** Real synthesis, placement and routing were
run on Lattice ECP5 LFE5U-25F (CABGA381) with Yosys 0.33 and nextpnr-ecp5,
using a 100 MHz timing constraint. The I/O pins are unconstrained because
no specific board was used. This is therefore a utilization and timing
study, not a board bitstream. Placement is randomized, so three seeds
(1, 2, 3) were run and the median is reported.
Post-route reports kept in this repository: `synthesis/nextpnr_top_module_report.json`,
`synthesis/nextpnr_sequential_matmul_report.json` (seed 1).

**Xilinx 7-series figures.** These come from Yosys `synth_xilinx`
technology mapping only. **They are pre-place-and-route estimates, not
Vivado results.** Regenerate the logs with `./synthesis/run_synthesis.sh`.

## 3. Cycle-level results (simulation)

| Metric | Systolic | Sequential | Ratio |
|---|---|---|---|
| Latency, start → done | **14 cycles** | **64 cycles** | 4.57× fewer |
| Sustained period per 4×4 product | **15 cycles** | **65 cycles** | 4.33× fewer |
| MAC operations per product | 64 | 64 | same |
| MACs performed in parallel (peak) | 16 | 1 | 16× |

### Where the 14 cycles go (measured from the VCD)

| Cycle after start edge | Controller state | Activity |
|---|---|---|
| 0 | CLEAR | accumulators and pipeline cleared |
| 1–7 | FEED | skewed operands leave the input buffers (steps 0–6, i.e. 2N−1 steps) |
| 3–12 | FEED/DRAIN | PE(i,j) accumulates in cycles 3+i+j … 6+i+j |
| 8–12 | DRAIN | last operands travel to PE(3,3) and pass through the MAC pipeline |
| 13 | CAPTURE | all 16 accumulators copied to `output_register` |
| 14 | DONE | `done` = 1 |

The general form for an N×N array of this design is
`1 (clear) + (2N−1) (feed) + (N+1) (drain) + 1 (capture) = 3N + 2` cycles.
For N = 4 that gives 14 cycles, which matches the simulation. The
sequential design needs N³ = 64 cycles.

### PE utilization

Each PE performs exactly N = 4 MACs per job (confirmed for all 16 PEs from
the VCD). At the sustained period, utilization is
64 MACs / (16 PEs × 15 cycles) = **26.7 %**. The array is idle while it
fills, drains, clears and captures. Section 7 discusses how to raise this.

## 4. FPGA results: Lattice ECP5-25F, post place-and-route

| Resource | Systolic | Sequential | Device total |
|---|---|---|---|
| LUT4 logic cells (TRELLIS_COMB) | 1 787 | 193 | 24 288 |
| Flip-flops (TRELLIS_FF) | 2 150 | 42 | 24 288 |
| Distributed-RAM write ports (TRELLIS_RAMW) | 32 | 17 | 3 036 |
| 18×18 multipliers (MULT18X18D) | **16** | **1** | 28 |
| I/O | 82 | 65 | 197 |
| Block RAM (DP16KD) | 0 | 0 | 56 |

Source: `synthesis/nextpnr_top_module_report.json`, `synthesis/nextpnr_sequential_matmul_report.json` (seed 1).

### Maximum clock frequency (post-route, three placement seeds)

| Seed | Systolic | Sequential |
|---|---|---|
| 1 | 102.01 MHz | 82.16 MHz |
| 2 | 122.04 MHz | 84.44 MHz |
| 3 | 127.83 MHz | 83.19 MHz |
| **Median** | **122.04 MHz** | **83.19 MHz** |

## 5. Time-domain comparison (derived arithmetic from sections 3 and 4)

| Metric (at median Fmax) | Systolic | Sequential | Speed-up |
|---|---|---|---|
| Latency per product | 14 / 122.04 MHz = **114.7 ns** | 64 / 83.19 MHz = **769.3 ns** | **6.7×** |
| Throughput | 122.04 / 15 = **8.14 M products/s** | 83.19 / 65 = **1.28 M products/s** | **6.4×** |
| Effective MAC rate | 520.7 MMAC/s | 81.9 MMAC/s | 6.4× |

At the *worst* seed for each design, the latency speed-up is
778.97 ns / 137.24 ns = 5.7×.

The time speed-up exceeds the cycle speed-up because the baseline's own
critical path is longer. Its LUT-RAM operand read feeds the multiplier and
adder in the same cycle. The baseline was intentionally left simple. A
pipelined baseline would narrow the clock-frequency gap but not the 4.3×
cycle advantage.

**Cost of the speed-up.** For 6.4× the throughput, the systolic design
uses 16× the multipliers, 9.3× the LUTs and 51× the flip-flops. Most of the
flip-flops are the inter-PE forwarding registers, the product pipeline
registers and the 544-bit output register. This is the classic trade of
area for parallelism.

## 6. Xilinx 7-series mapping (Yosys estimate, not post-route)

| Cell | Systolic | Sequential |
|---|---|---|
| DSP48E1 | 16 | 1 |
| FDRE (flip-flops) | 838 | 8 |
| LUT1–LUT6 | 384 | 51 |
| RAM32M (LUT-RAM) | 24 | 12 |
| CARRY4 | 15 | 0 |

The flip-flop count is lower than on ECP5 because Yosys absorbs the
accumulator and some pipeline registers into the DSP48E1 internal
registers. Source: Yosys `synth_xilinx` logs, regenerated by
`./synthesis/run_synthesis.sh`.

## 7. Design-space decisions (measured, with evidence kept in the repository)

1. **Read-mux rewrite.** The first version indexed the result bus with
   `result[rd_addr*ACC_W +: ACC_W]`. Yosys turned the variable multiply into
   an extra DSP48E1 plus a 544-bit shifter. Rewriting it with constant
   part-selects changed the 7-series mapping as follows:
   cells 2 495 → 1 455, DSP 17 → 16, LUTs 1 411 → 382.
   Function unchanged (all tests re-run). The rewritten read mux is the
   shipped `rtl/matrix_interface.v`.
2. **Pipelined MAC.** With multiply and accumulate in one cycle, the
   critical path ran forwarding register → 18×18 multiplier → 34-bit adder.
   Adding a product register:

   | | Seed 1 | Seed 2 | Seed 3 | Median | Latency | Time per job (median) |
   |---|---|---|---|---|---|---|
   | 1-stage MAC | 97.16 | 95.71 | 91.00 MHz | 95.71 MHz | 13 cyc | 135.8 ns |
   | 2-stage MAC (shipped) | 102.01 | 122.04 | 127.83 MHz | 122.04 MHz | 14 cyc | **114.7 ns** |

   The extra cycle of latency is outweighed by the higher clock, so the
   2-stage MAC was kept. On seed 1 alone the 1-stage design would have
   looked marginally better (133.8 ns vs 137.2 ns), which is why several
   seeds were run before deciding. The shipped MAC is
   `rtl/mac_unit.v`.

## 8. Limitations and improvement opportunities

* **Utilization (26.7 %).** Jobs do not overlap. Feeding job *n+1* while
  job *n* drains needs either double-buffered accumulators or result
  shifting out of the array. That would bring the steady-state period
  towards 2N−1 = 7 cycles.
* **Interface bandwidth.** Loading takes 32 write cycles per job through
  the 16-bit port, which is far more than the 14-cycle compute. A real
  system would use wider or streaming (AXI-Stream) input ports.
* **Fmax.** The remaining critical path is the hard multiplier plus routing.
  The ECP5 multiplier's internal input/output registers are not used by
  the current Yosys mapping. Board-specific pin constraints would also
  change routing.
* **Scale.** The design is parameterized by N, but only N = 4 was verified
  and synthesized.

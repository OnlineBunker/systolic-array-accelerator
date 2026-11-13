#!/usr/bin/env python3
"""Independent NumPy reference model for the 4x4 systolic array accelerator.

Recomputes C = A x B for the testbench's graded cases with exact Q8.8
fixed-point integer arithmetic, independent of the Verilog implementation,
and cross-checks the hardware results recorded in
``simulation/logs/sim_top_module.log``.

Run from the repository root:

    python3 docs/reference_model.py

Exit status 0 means every hardware element matches this model.
"""

import re
import sys
from pathlib import Path

import numpy as np

LOG = Path(__file__).resolve().parent.parent / "simulation" / "logs" / "sim_top_module.log"

Q = 8  # fractional bits of the Q8.8 operands


def to_q88(x: np.ndarray) -> np.ndarray:
    """Quantize decimal values to signed Q8.8 integers (round half up)."""
    return np.floor(x * (1 << Q) + 0.5).astype(np.int64)


def matmul_raw(a_q: np.ndarray, b_q: np.ndarray) -> np.ndarray:
    """Full-precision integer accumulation, exactly as the hardware does.

    Products are Q16.16; the accumulator keeps every bit (34 bits are
    provably enough for N = 4), so the integer sum cannot overflow.
    """
    n = a_q.shape[0]
    acc = np.zeros((n, n), dtype=np.int64)
    for i in range(n):
        for j in range(n):
            acc[i, j] = sum(int(a_q[i, k]) * int(b_q[k, j]) for k in range(n))
    return acc  # value = acc / 2**16


def to_q88_out(acc: np.ndarray) -> np.ndarray:
    """Hardware rd_q88: round to nearest and saturate to signed 16 bits."""
    rounded = np.floor((acc + (1 << (Q - 1))) / (1 << Q)).astype(np.int64)
    return np.clip(rounded, -(1 << 15), (1 << 15) - 1)


# The graded cases, identical operands to testbench/tb_top_module.v.
CASES = [
    (
        "TEST CASE 2: general integer matrices",
        np.array([[1, 2, 3, 4], [5, 6, 7, 8], [9, 1, 2, 3], [4, 5, 6, 7]], dtype=float),
        np.array([[1, 2, 0, 1], [0, 1, 2, 0], [1, 0, 1, 2], [2, 1, 0, 1]], dtype=float),
    ),
    (
        "TEST CASE 3: negative and fractional values",
        np.array([[-1.5, 0.25, 2.5, -0.125], [3.125, -2.0, -0.375, 0.5],
                  [-1.0, -1.0, -1.0, -1.0], [0.004, -0.004, 7.812, -7.0]], dtype=float),
        np.array([[0.75, -0.5, 1.0, 0.0], [-2.75, 4.5, -0.25, 1.0],
                  [0.125, -0.125, -5.0, 1.5], [-1.0, 9.0, 0.312, -2.5]], dtype=float),
    ),
    (
        "TEST CASE 4: extreme values (-128.0 x -128.0)",
        np.full((4, 4), -128.0),
        np.full((4, 4), -128.0),
    ),
]


def hardware_values(log_text: str, case_name: str) -> np.ndarray:
    """Parse the 4x4 'hardware' result column for one case from the log."""
    block = log_text.split(f"=== {case_name} ===")[1]
    rows = []
    for line in block.splitlines():
        m = re.match(r"\s+(-?\d+\.\d{3})\s+(-?\d+\.\d{3})\s+(-?\d+\.\d{3})\s+(-?\d+\.\d{3})\s+\|", line)
        if m:
            rows.append([float(g) for g in m.groups()])
        elif rows:
            break
    return np.array(rows)


def main() -> int:
    log_text = LOG.read_text()
    failures = 0
    for name, a, b in CASES:
        acc = matmul_raw(to_q88(a), to_q88(b))
        model = acc / float(1 << (2 * Q))
        hw = hardware_values(log_text, name)
        ok = hw.shape == (4, 4) and np.allclose(hw, model, atol=5e-4)
        print(f"{name}")
        print("  model C (full precision):")
        for row in model:
            print("   " + " ".join(f"{v:10.3f}" for v in row))
        sat = to_q88_out(acc)
        if (sat != np.floor((acc + (1 << (Q - 1))) / (1 << Q))).any():
            print(f"  note: rd_q88 saturates to {sat.min()}-{sat.max()} raw LSBs (overflow flag set)")
        print(f"  cross-check vs {LOG.name}: {'PASS' if ok else 'FAIL'}")
        failures += 0 if ok else 1
    print(f"\n{len(CASES) - failures}/{len(CASES)} cases match the hardware log")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

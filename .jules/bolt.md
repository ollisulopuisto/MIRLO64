## 2026-11-02 - Hoisting Closures and Replacing Dict Hashing in Python Spec Models

**Learning:** In high-volume test verification harnesses (like `pad_test.py`), defining helper functions inside hot loops creates tens of thousands of function closure objects and stack frame setup overhead. Additionally, indexing 5-bit integer fields through Python dicts (`.get()`) incurs hash calculation and collision check overhead compared to direct indexing into precomputed flat lists (`CODE_BIT_LUT`, `OUT_LUT`).
**Action:** When validating thousands of hardware states against reference specs in Python test scripts, hoist helper functions outside test dispatch loops and precompute flat array lookups for bounded integer ranges (e.g., 0..31).

## 2026-11-05 - Selective Stderr/Stdout Line-Buffering in Shared C Test Harnesses

**Learning:** When C test helper binaries (like `pad_host.c`) are shared between high-throughput batch test runners (`pad_test.py` processing 21k+ lines at once) and interactive per-assertion runners (`ctrl_test.py`), unconditionally enabling `setlinebuf(stdout)` causes a significant throughput penalty in batch tests due to tens of thousands of individual write syscalls. Conversely, default block-buffering deadlocks interactive line-by-line callers over pipes.
**Action:** Guard line-buffering in C test harnesses behind a command-line flag (`-u`), allowing interactive test scripts to maintain persistent subprocess communication without process spawn overhead while batch runners retain high-throughput block buffering.

## 2026-11-11 - Precomputing Bounded Bitmask LUTs vs High-Entropy Keyspace Arrays

**Learning:** When evaluating bitwise hardware state mappings in Python (e.g. `pad_test.py`), precomputing full 16-bit tables (65,536 elements) introduces significant module-level initialization overhead (~280ms) that can negate loop savings on sub-second test runs. However, isolating the low-entropy subfield (such as 4-bit D-pad masks with 16 states) reduces the lookup table setup to <0.1ms while completely eliminating repeated boolean comparisons, branch evaluations, and vector construction across 21k+ hot-path evaluations.
**Action:** When replacing boolean arithmetic or bit manipulation with LUTs in ephemeral test scripts, project the input down to the minimal subfield (e.g. `k_mask & DPAD_MASK`, 16 entries) instead of constructing large keyspace lookup arrays.

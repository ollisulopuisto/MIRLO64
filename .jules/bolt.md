## 2026-11-02 - Hoisting Closures and Replacing Dict Hashing in Python Spec Models

**Learning:** In high-volume test verification harnesses (like `pad_test.py`), defining helper functions inside hot loops creates tens of thousands of function closure objects and stack frame setup overhead. Additionally, indexing 5-bit integer fields through Python dicts (`.get()`) incurs hash calculation and collision check overhead compared to direct indexing into precomputed flat lists (`CODE_BIT_LUT`, `OUT_LUT`).
**Action:** When validating thousands of hardware states against reference specs in Python test scripts, hoist helper functions outside test dispatch loops and precompute flat array lookups for bounded integer ranges (e.g., 0..31).

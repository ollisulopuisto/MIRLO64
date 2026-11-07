## 2026-11-07 - RSP Timing Model Bottlenecks

**Learning:** The RSP timing model in `sim/rsp/rsp_time.c` is the primary simulation bottleneck — it's called per-instruction in the loop and uses bit-field ops, loops, and `memset` on every reset. Verilator simulates the actual RTL, but the `rsp_time.c` model is used by `rsp_task -t` and `tb_rsp CYCLES=1` for cycle-exact verification.

**Action:** Target the `decode()` function's bit-field operations, the `push()` function's cascading array shifts, and the `rsp_time_reset` memset. These are hot paths called on every instruction cycle.

## 2026-11-07 - Inlined decode() in rsp_time_slot (PR #10)

**Learning:** Inlining `decode()` into `rsp_time_slot()` eliminates 1-2 redundant decode invocations per stall cycle. The decode switch statement is expensive (64-case, multiple nested ifs), and during stalls the inner loop calls `rsp_time_ready()` which re-decodes both instructions each cycle. Caching decode results in locals and inlining the `pairs()`/`ready()` condition checks removes this overhead entirely.

**Action:** For future timing-model optimizations, always check whether the hot loop re-calls decode on every iteration — cache results in locals and inline the helper conditions.

## 2026-11-07 - Inlined rsp_time_issue() in rsp_time_slot (PR #10)

**Learning:** `rsp_time_slot()` already decodes both instructions into d0/d1, but then calls `rsp_time_issue()` → `slot()` which decodes them again — 2 redundant decodes per slot. Inlining the issue logic (merge d0/d1 into u, push, counters) using the cached decodes skips those 2 decodes entirely.

**Action:** `rsp_time_issue()` is public API (called by tb_rsp.cpp) so its signature stays; only `rsp_time_slot()` inlines it. Combined win: ~27% (24 → 16 ns/instr), cycle counts identical (disproof: seed-42 task gives 1031 cycles before and after).

## 2026-11-07 - Failed optimizations in rsp_time.c (no measurable win)

**Learning:** Three candidate optimizations were tried and rejected — all within run-to-run noise:

1. **`word()` bswap** (`sim/rsp/rsp_time.c`): replaced 4 byte loads + shifts with `memcpy` + `__builtin_bswap32`. Clang -O2 already generates optimal code for this pattern. Result: ~23.7 vs ~23.7 ns/instr (identical).

2. **`push()` ring buffer** (`sim/rsp/rsp_time.c`, `rsp_time.h`): replaced the 9-assignment cascade with a ring buffer index (`h_idx`). The index computation at read sites (`h_prev()`) cancels the push() savings. Result: ~24.0-25.1 vs ~23.8-24.5 ns/instr (overlapping).

3. **`dma_update()` branchless** (`sim/rsp/rsp_time.c`): replaced `if (s->dma_busy) t->dma_wait++;` with `t->dma_wait += busy;`. Within noise: 3062-3273 ms vs 3062-3125 ms for 200 rsp_task runs.

4. **`dma()` modulo→mask** (`sim/rsp/rsp.c`): replaced `(ram + i) % s->rdram_size` with `(ram + i) & (s->rdram_size - 1)`. `dma()` is called once per DMA setup (rarely), not per cycle. Within noise.

**Action:** The rsp_time.c hot paths are already well-optimized by Clang -O2. Remaining measurable gains would require algorithmic changes (e.g., jump table for decode switch) rather than micro-optimizations. No further valid targets found in sim/rsp/.

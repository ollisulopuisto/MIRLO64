## 2026-11-07 - RSP Timing Model Bottlenecks

**Learning:** The RSP timing model in `sim/rsp/rsp_time.c` is the primary simulation bottleneck — it's called per-instruction in the loop and uses bit-field ops, loops, and `memset` on every reset. Verilator simulates the actual RTL, but the `rsp_time.c` model is used by `rsp_task -t` and `tb_rsp CYCLES=1` for cycle-exact verification.

**Action:** Target the `decode()` function's bit-field operations, the `push()` function's cascading array shifts, and the `rsp_time_reset` memset. These are hot paths called on every instruction cycle.

## 2026-11-07 - Inlined decode() in rsp_time_slot (PR #10)

**Learning:** Inlining `decode()` into `rsp_time_slot()` eliminates 1-2 redundant decode invocations per stall cycle. The decode switch statement is expensive (64-case, multiple nested ifs), and during stalls the inner loop calls `rsp_time_ready()` which re-decodes both instructions each cycle. Caching decode results in locals and inlining the `pairs()`/`ready()` condition checks removes this overhead entirely.

**Action:** For future timing-model optimizations, always check whether the hot loop re-calls decode on every iteration — cache results in locals and inline the helper conditions.

## 2026-11-07 - Inlined rsp_time_issue() in rsp_time_slot (PR #11)

**Learning:** `rsp_time_slot()` already decodes both instructions into d0/d1, but then calls `rsp_time_issue()` → `slot()` which decodes them again — 2 redundant decodes per slot. Inlining the issue logic (merge d0/d1 into u, push, counters) using the cached decodes skips those 2 decodes entirely.

**Action:** `rsp_time_issue()` is public API (called by tb_rsp.cpp) so its signature stays; only `rsp_time_slot()` inlines it. Win: ~14% (18.6 → 16.0 ns/instr), cycle counts identical (disproof: seed-42 task gives 1031 cycles before and after).

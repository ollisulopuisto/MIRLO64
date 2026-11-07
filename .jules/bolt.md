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

## 2026-11-07 - N64 CPU fetch inlining (PR #11)

**Learning:** `n64_cpu_step()` in `sim/n64/cpu.c` calls `n64_read()` → `phys()` → `n64_read_phys()` for every instruction fetch. For KSEG0 addresses (where nearly all game code runs), `phys()` is just a bitmask and `n64_read_phys()` is just an RDRAM bounds check + pointer read. Inlining this fast path directly in `n64_cpu_step()` skips 2 function calls per instruction fetch. The `pc & 3 == 0` alignment check already guarantees word alignment, so `*(uint32_t *)(rdram + (pc & 0x1FFFFFFF))` is bit-identical to `rd32()`.

**Action:** ~28% win (7.3 → 5.1 ns/step, no overlap in 20-run distribution). Falls through to original `n64_read()` for non-KSEG0 addresses and KSEG0 addresses outside RDRAM (ROM, registers). Correctness verified for KSEG0, KSEG1, and ROM fetch paths.

## 2026-11-07 - N64 data bus fast-path inlining (PR #13)

**Learning:** After PR #11 inlined KSEG0 instruction fetches in `n64_cpu_step()`, data loads/stores still go through `n64_read()` → `phys()` → `n64_read_phys()` for every access. For KSEG0 RDRAM addresses (the vast majority of data accesses), `phys()` is just `va & 0x1FFFFFFF` and `n64_read_phys()` is just an RDRAM bounds check + pointer read. Inlining this fast path directly in `n64_read()`/`n64_write()` skips 2 function calls and a branch chain per data access.

**Action:** ~16-27% win (read: 4.4 → 3.7 ns/op; write: 5.0 → 3.7 ns/op, no overlap in steady-state distributions). Falls through to original `phys()`/`n64_read_phys()`/`n64_write_phys()` for non-KSEG0 addresses and KSEG0 addresses outside RDRAM (ROM, registers). Correctness verified for KSEG0/KSEG1 RDRAM (word, half, byte), write-read consistency, ROM (TLB_MISS), and past-RDRAM (-1).

## 2026-11-07 - Wild goose chase: failed optimizations outside rsp_time.c

**Learning:** Three more candidates tried and rejected — all within run-to-run noise:

1. **`dither_n64()` unroll** (`lang/c/rdp/rdp.c`): replaced the per-channel pointer-array loop with unrolled per-channel code. Result: ~2953-3180 ms vs ~2992-3181 ms for 100 rdp_task runs (overlapping).

2. **`draw_pixel` inline** (`lang/c/rdp/rdp.c`): added `static inline` to enable loop-invariant hoisting in the per-span pixel loop. Result: ~3044-3224 ms vs ~3031-3246 ms for 100 rdp_task runs (overlapping).

3. **`phys()` TLB last-hit cache** (`sim/n64/bus.c`, `n64.h`): added `tlb_last` field and started the TLB scan from the last matching entry. The modulo/branch overhead cancelled any benefit. Result: ~4.5-5.0 ns/read vs ~3.3-3.6 ns/read baseline (actually slower).

**Action:** Clang -O2 already generates near-optimal code for these patterns. The only wins come from eliminating entire function call layers (RSP decode inlining, N64 CPU fetch inlining, N64 data bus fast path), not from micro-optimizing what's already there.

## 2026-11-07 - Per-process startup cost: RSP reciprocal ROM build

**Learning:** For the short tasks the host tools run (`rsp_task`, `rdp_task`, `tb_rsp`, `tb_dpc`, `tb_rdp`), the hot spot was not the interpreter but `make_roms()` in `sim/rsp/rsp.c` (first `rsp_reset`): the inverse-square-root table was built by a linear search from 2^17 (~15M steps, ~16 ms per process). `sim/rsp/make_div_rom.py` mirrors it and took ~3 s in CI. Bisection in C and `math.isqrt` in Python give byte-identical tables.

**Action:** Profile whole short runs with `perf record` before optimizing per-instruction code: one-time setup can dominate. The Python script generates `rtl/rsp/rsp_div_rom.hex` for the RTL (`$readmemh`) and must match the C model's tables, so change both together.

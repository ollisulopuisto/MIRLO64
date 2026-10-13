# Save states and sleep: plan and plausibility

Status: a plan from a read-only survey of the code (2026-10-13). Nothing here has been built, simulated or run on a Pocket, and the file references
come from the survey, not from a second check. `core.json` has `"sleep_supported": false` and the savestate wires in `target/pocket/core_top.sv`
are undriven, so the core reports "unsupported" today.

## The Pocket's side (Analogue's host/target commands)

- `0x00A0` Savestate: Start/Query. Parameter bit 0 asks to start; the answer is three words: supported, the blob's address, its size. Result codes:
  0 idle, 1 busy, 2 done, 3 error. The core may allow or deny each request.
- `0x00A4` Savestate: Load/Query. Same shape; the answer gives the address to write the blob to and the maximum size.
- `target/pocket/core_bridge_cmd.v` implements both commands (`savestate_supported/addr/size/maxloadsize`, start/load with ack, busy, ok, err); nothing drives them.
- Sleep (`"sleep_supported": true`) uses the same two commands.
- **Not documented, and the first thing to settle:** the largest blob the Pocket accepts, and what halting the core cleanly must look like.

## What the core can give

- The runtime (`n64rt`, `OWN=1`) saves the game CPU's whole context on every monitor entry (`n64rt_mon_ctx`: GPRs, HI/LO, FPRs, FCSR, Status, Count, EPC). Parking the game is not returning from the monitor; Count is frozen meanwhile and restored on exit.
- The bridge already writes and reads SDRAM. A blob window of about 12 MiB exists with no new RTL: the free area (SDRAM `0x0334_1100..0x037F_FFFF`, includes the RDP's coverage plane) and the 8 MiB RDRAM (`0x0380_0000..`), addressed through the bridge at `0x0400_0000 + SDRAM address` (not `0x0400_0000..0x040F_FFFF`).
- Cartridge saves (128 KiB) and the Controller Pak (32 KiB) live in SDRAM. The D-cache is write-through; flush functions exist. The TLB is the runtime's software table (restore it and flush).
- Readable and writable by software: MI interrupt state, VI registers (through the runtime's `hw_rd`/`hw_wr`), PIF RAM, RSP DMEM/IMEM through SP DMA while the RSP is halted, RSP PC, the DPC registers.

## What has no read path today

RSP vector registers, accumulators and flags; all RDP internal state including TMEM; the AI's queued second buffer and resampler phase; `rcp_si` internals;
the LL bit (a restore gives at most one spurious SC failure); the VI scan-out phase.

Policy: snapshot only when the RSP is halted and its DMA idle, the RDP idle (`R_MRDP_STATUS`), and the PI and SI idle. Assume the game's display lists
re-emit the RDP state each frame (unverified: TMEM may carry over). After a restore the AI queue is empty while the game thinks buffers are queued; re-raise
the AI interrupt (`MIRAISE`) so the game requeues (untested).

## Steps

1. **Spec:** find the Pocket's blob size limit with a dummy blob that grows in steps. The window is about 12 MiB.
2. **Runtime:** a save request (a CSR flag or `MONITOR.PEND` bit) is taken at the next vblank in `n64rt_rcp_events`. Wait for the idle conditions, retrying at the next
   vblank after a timeout (a 30 fps game or a long gfx task may rarely be idle at vblank). Copy the runtime's state (BSS, GPR context, DMEM and IMEM, PIF RAM,
   VI/MI/AI registers, header) into the free area, then report the blob ready. Load: the reverse, then flush both caches, `tr_flush`, re-base the `uptime`-based
   variables (`uptime` restarts at reset), reconcile the VI/MI interrupt state, and eret.
3. **RTL (small):** drive `savestate_supported/addr/size/maxloadsize` and the handshake from a register, across the clock-domain crossing. This needs a new fit (3 of 16 seeds closed last time, design at about 95 % of the ALMs).
4. **Hardware:** Mario 64 first, then games with long gfx tasks; set `"sleep_supported": true` only after save and load work. A load needs the same ROM and a freshly booted core.

## Risks

The Pocket's size limit; the AI after a restore; RDP state that carries across frames; timing closure of the new fit; games that are never idle at vblank;
audio is silent while parked. Expect some games to glitch for a few frames after a load.

## Unknown

The runtime's BSS size; whether an SP DMA of DMEM refreshes the RDP's XBUS copy; whether the Pocket accepts about 12 MiB.

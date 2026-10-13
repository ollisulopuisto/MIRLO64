# Debug aids: the FPS counter and the graph

Core Settings > **Debug** is a list (id 276, not remembered between starts), written to `0x1000_0124`, field 9, `interact1[9:5]`: **Off**, **FPS**,
**Graph**, **FPS and graph**. Bit 0 of its value is the FPS counter below (RTL); bit 1 is the graph (the runtime's, next section). Before this the
counter was a checkbox, "Show FPS" (id 238, field 15, `interact1[25]`).

## The graph

`lang/n64rt/n64rt_dbg.h` (host test: `lang/n64rt/test/dbg_test.py`), sampled and drawn by `n64rt_io.c`'s `dbg_tick`. Needs no new bitstream, only `n64rt.sys`.
At each monitor tick (four a field) the runtime samples what the game CPU, the RSP and the RDP are doing, and draws the graph into the frame buffer the VI
shows (top left at pixel (4, 12), 96 x 32 pixels, redrawn at every tick so that a game redrawing its frame does not wipe it). One column is a window of 60
ticks (a quarter of a second); the newest is at the right, so the graph shows about 24 seconds. Four bands from the top, 8 pixels each, a bar grows from the
band's bottom (a full band is 100 %):

| Band | Meaning |
|---|---|
| red | the game CPU busy: the share of samples whose PC was not the idle thread (`b .`, 0x1000FFFF, at the PC or the word before it; a game with another idle loop reads as busy) |
| green | the RSP running (SP_STATUS not halted) |
| blue | the RDP drawing (the MRDP not idle) |
| white | the game's frames (frame buffer swaps) in the window, two to a pixel: 60 fps is a full band, 30 fps half |

A sample is a sample: four a field, so one window of 60 is a few per cent noisy, and the monitor's own entries and the drawing (a few thousand uncached
stores a tick) cost a little CPU time. Not seen on a Pocket yet. A frame buffer of an odd width is not drawn on in 16-bit colour.

## The FPS counter

The menu pattern comes from the related [MIRLO core](https://github.com/tortugaveloz/MIRLO)
and its [Super Mirlo 64 port](https://github.com/tortugaveloz/supermirlo64).
Verified donor revisions:

- MIRLO `4a139bfe92f956092558c882bb1105e18fd26390`: the `Show FPS` checkbox
  in `pkg/pocket/Cores/tortuga.Mirlo/interact.json`.
- supermirlo64 `b038cb8371d1d40428c6008e352ac83847a6d308`:
  `platform/fps_overlay.c` reads that option and draws `frame_fps` through
  SM64's display-list/font code. That game-specific renderer is not copied:
  MIRLO64 runs arbitrary ROMs and does not have those game-engine functions.

Instead, this patch connects MIRLO64's existing `n64_video.sv` generic FPS
counter and glyph overlay to a menu option, through `mirlo_regs.sv` and
`mirlo_mips.sv`. It adds a two-flop synchronizer for the option's passage
from the system clock to the video clock. No game ROM changes are needed.

## What the number means

Two white decimal digits appear at active-screen position (4, 4), in a
16x8 black box. The counter counts VI framebuffer-origin changes over the
last 60 NTSC refreshes (approximately one second) or 50 PAL refreshes.
It updates once per such interval. This is a presentation-rate proxy,
not the game's logic-update rate, RDP completion rate or host display Hz.
Repeated frames using the same origin are not counted; rewriting a buffer
in place may undercount, and extra origin writes may overcount. The inherited
counter is two-digit BCD and wraps after 99. Its window-boundary cycle takes
priority over an origin change on that same cycle. The inherited BCD
clock crossing can briefly show mixed digits at an update; no timing-critical
logic depends on the display.

The overlay is separate from the debug OSD (which has priority if enabled).
It is drawn above the crop/black output, so the default vertical crop does not
hide the digits. This patch leaves the original counting and font code intact.

## Build and install

Unlike the controller mapping patch, this changes RTL and **requires a new
FPGA bitstream**. A runtime-only rebuild will not enable it.

Use the repository README's toolchain/library/boot-ROM/RSP-ROM setup first.
With those generated files and Quartus already set up, from the repository root:

```sh
python3 tools/mips_inits.py
(cd projects && quartus_sh --flow compile mirlo)
python3 tools/package_bitstream.py projects/output_files/mirlo.rbf mirlo.rev
```

Back up the existing SD-card files. Copy `mirlo.rev` to
`Cores/tortuga.Mirlo64/` and the patched
`pkg/pocket/Cores/tortuga.Mirlo64/interact.json` to that same directory.
Reload the core and choose **FPS** in Debug. No runtime rebuild is needed for
this FPS patch alone. If using the controller patch too, rebuild/copy its
`n64rt.sys` as described in its README and install the combined menu file.

## Tests

With Verilator and a C++ compiler on PATH:

```sh
sh sim/fps/run.sh
```

The test checks the option's reset/enable/disable and that field writes do not
clobber the controller bit. It checks NTSC/PAL windows, zero, decimal carry,
and overlay on/off by capturing the actual RTL video output. It saves
`fps-on.ppm` and `fps-off.ppm` in the current directory for inspection.

The test passed with Verilator 5.38. The simulated enabled frame showed `30`
at the top left; the disabled frame had no overlay pixels. Full Quartus fitting
and physical Pocket testing have not been performed for this patch.

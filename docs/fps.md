# Optional FPS overlay

Core Settings > **Show FPS** is a default-off checkbox (id 238), written to
`0x1000_013C`, field 15, `interact1[25]`. Field 14 (`interact1[24]`, id 237) was the C-button
layer, now replaced by the remap table (docs/mips.md).

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
Reload the core and enable **Show FPS**. No runtime rebuild is needed for
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

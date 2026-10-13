# Debug aids: the frame rate and the graph

Core Settings > **Debug** is a list (id 276, not remembered between starts), written to `0x1000_0124`, field 9, `interact1[9:5]`: **Off**, **FPS**,
**Graph**, **FPS and graph**. Bit 0 of its value is the frame rate as a number, bit 1 the graph; both are drawn by the runtime into the frame buffer the VI shows
(the earlier RTL counter, a checkbox "Show FPS", drew on the video block's OSD, which upstream removed with its 640 x 240 rewrite).

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

## The frame rate

`n64rt_dbg_draw_number`: up to three digits (3 x 5 pixel font, scaled by two) at pixel (4, 46) with the graph on, (4, 12) without. It is the number of
frame buffer swaps (`n64rt_swaps`) in the last 240 ticks, about a second: the frames the game showed, not its logic rate. A game that shows a
buffer twice (30 fps in 60 Hz) reads 30. The number is drawn at every tick like the graph.


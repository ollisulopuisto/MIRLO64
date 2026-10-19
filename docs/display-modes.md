# Pocket display modes (fork)

`Screen Size` is a Pocket-only setting at bridge address `0x10000158` (interact word 22, ID 237). Its menu order and stored
values are:

| Mode | Value | Framing |
|---|---:|---|
| Original | 0 | Default; the scan-out's 640 × 240 picture, shown 4:3, with the existing crop masks |
| Fit (keep aspect) | 2 | As Original: the whole field, the picture's bars black |
| Fill (stretch) | 1 | The picture fills the display: each axis scaled by the Pocket independently |
| Hybrid | 4 | Between Stretch and aspect-correct Overscale: the 8 % at the sides cropped, 10 % squeezed |
| Fill (overscale) | 3 | Aspect kept, the overflow cropped (centred) |

None of the modes has a frame store or any delay: the scan-out's own stream is cut to the rectangle of a scaler preset
(`pkg/pocket/Cores/tortuga.Mirlo64/video.json`), and the preset is announced to the Pocket in the scan-out's slot word.
No mode changes the game's rendering resolution or the memory interfaces. (An earlier version of the fork held a frame in
the PSRAM and filtered it; the PSRAMs now hold the ROM, see [mips.md](mips.md).)

## Picture bounds and the presets

The scan-out exports its picture's bounds (`picture_x`, `_y`, `_w`, `_h`): the VI window less the Crop Vertical and Crop
Right bands, in the field's own pixels and lines. Black bars drawn inside a game's framebuffer remain a part of the picture:
detecting black pixels would zoom dark scenes. Overscale and Hybrid can crop HUD elements.

`rtl/soc/n64_video.sv` sends the stream; `target/pocket/pocket_frame.sv` follows its DE, picks the preset from the setting and
the bounds and drops DE outside the preset's rectangle (the Pocket's scaler counts the pixels and lines of DE). A pixel
stays what the scan-out made it: no resampling, so every mode is bit-exact.

| Slot | Output pixels | Pocket aspect | Dock aspect | Used for (picture bounds *w* × *h*) |
|---|---|---|---|---|
| 0 | 640 × 240 | 4:3 | 4:3 | Original, Fit, and every setting whose preset does not fit the picture |
| 1 | 640 × 480 | 4:3 | 4:3 | A woven (interlaced) frame, in every mode |
| 2 | 640 × 240 | 10:9 | 16:9 | Stretch: *w* 600 – 640, *h* 225 – 240 |
| 3 | 640 × 224 | 10:9 | 16:9 | Stretch: *w* 600 – 640, *h* up to 224 (and the picture's first line at most 16) |
| 4 | 640 × 216 | 10:9 | 16:9 | Stretch: *w* 600 – 640, *h* up to 216 (and the picture's first line at most 24) |
| 5 | 520 × 234 | 10:9 | 4:3 | Overscale on the Pocket: *w* ≥ 520, *h* 234 – 240 (centred) |
| 6 | 480 × 216 | 10:9 | 4:3 | Overscale on the Pocket: *w* ≥ 480, *h* 216 – 233 (centred) |
| 7 | 588 × 240 | 10:9 | 11:9 | Hybrid: *w* ≥ 588, *h* 200 – 240 (the field's lines, the picture's centred columns) |

A VI sample is half as wide as it is tall (640 × 240 shown 4:3 has 1:2 pixels), so slot 5 – 6 are the exact 10:9 cover of the
Pocket's screen; slot 7 crops 26 columns a side, a 10 % vertical stretch against 1.20 of Stretch. The rectangle is centred in
the picture's window (slots 5 – 7); slots 3 – 4 start at the picture's first line; slots 2 – 4 are the whole 640 columns
(a pad of up to two black columns where Crop Right took them).

A setting whose preset does not fit the picture (a 320-wide window, an odd height, Overscale at 213 rows, Hybrid at 224
rows) is shown as slot 0, as Original. Overscale on the Dock is slot 0 too: 640 × 240 already fills a 4:3 display.

**Fork: 16:9 on the Dock.** Slots 2 – 4 (Fill (stretch)) specify 16:9 on the Dock (`dock_aspect` in `video.json`), so on a 16:9
display Fill (stretch) fills the screen -- the way for games that squeeze a 4:3 picture for 16:9 (Perfect Dark's widescreen
option); the other modes stay 4:3 there. Slot 7 is 11:9 (the 4:3 picture with its 8 % cropped).

## The announcement

The Pocket takes a preset from the slot word the core sends in the clocks after a line's DE (`rgb[15:13]`), for the **next**
frame. `pocket_frame` takes the slot of the next frame from the bounds of the frame it is sending, as each line's DE ends,
and keeps the bounds it made it on. A frame whose bounds are not those of the announcement (a game changing its window or the
setting, or a woven frame announced as a progressive one) is sent black in the announced shape, and the next one is right.
A change of setting takes effect after one or two frames.

## Tests

`sh sim/pocket_frame/build.sh` (Verilator, a C++ compiler) feeds `pocket_frame` the scan-out's stream with chosen bounds and
compares every pixel, the lines of each preset, the slot words and the black frame of a change with a model, for every mode,
Pocket and Dock. `sim/vi_filter/regress.sh` checks the scan-out, including the exported bounds, against its own model.

`projects/fits.json` must record a fit of the current sources.

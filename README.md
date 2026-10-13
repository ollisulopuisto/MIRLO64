# MIRLO 64

MIRLO 64 is an N64 core made specifically to fit in the Analogue Pocket. It intends to replicate as best as possible the N64 architecture.

## Installing on the Pocket

1. Download `tortuga.Mirlo64_<version>.zip` from the [releases](https://github.com/tortugaveloz/MIRLO64/releases).
2. Unzip it onto the **root** of the Pocket's SD card, merging with the folders already there. It adds only Mirlo's own files:

   ```
   Assets/mirlo/common/          n64rt.sys (the runtime) and n64savedb.txt; where Mirlo's games go
   Cores/tortuga.Mirlo64/        the core: mirlo.rev (the bitstream), core.json, ...
   Platforms/mirlo.json          the platform, under Console
   Platforms/_images/mirlo.bin   its image
   ```

3. Put the games (games in `.z64` format) in `Assets/mirlo/common/`.
4. On the Pocket: **openFPGA → Console → Nintendo 64**, then pick a game.

Saves (`.sav`) appear in `Saves/mirlo/common/` when you quit a game. To update the core, unzip a newer release the same way; it replaces the files in `Cores/tortuga.Mirlo64/`.

## Display size

**Core Settings → Screen Size** offers:

- **Original** (default): the existing 320 × 240, 4:3 presentation.
- **Fit (maintain aspect ratio)**: enlarge the selected picture while keeping all of it visible.
- **Fill screen (stretch)**: fill the display by scaling each axis independently.
- **Hybrid**: fill the display with half the source crop of ideal Overscale and approximately half the distortion of Stretch.
- **Fill screen (overscale)**: preserve proportions and crop the centred overflow; this can hide HUD elements.

The additional modes remove the core's padding and apply **Crop Vertical**
and **Crop Right** before scaling. Borders drawn inside a game's framebuffer
remain. Native pixels are retained for supported picture sizes; other sizes
and Hybrid use bilinear filtering. These modes add approximately one frame
of delay (17 ms NTSC / 20 ms PAL). Original retains its existing latency.
Dock uses a 4:3 output area; the Pocket panel is 10:9.

Install the rebuilt `mirlo.rev`, `video.json` and `interact.json` together,
then fully quit and reload the core. See [display modes](docs/display-modes.md)
for preset coverage, implementation details, tests and hardware validation.

## License

MIRLO 64 is released under the [Apache License 2.0](LICENSE).

This development is AI assisted.

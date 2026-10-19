#!/bin/bash
# The real scan-out (sim/vi_filter's tb_vi, which dumps a frame as TB_STREAM) through pocket_frame, for the VI windows games use, every Screen
# Size setting, Pocket and Dock: the preset its bounds ask for must come out pixel for pixel and be announced. Needs both benches built
# (sim/vi_filter/build.sh, sim/pocket_frame/build.sh). Prints every case; exit status 1 on a mismatch.
HERE="$(cd "$(dirname "$0")" && pwd)"; VI="$HERE/../vi_filter"; PF="$HERE/obj_dir/tb_pocket_frame"
ST="$(mktemp -d)"; rc=0
run() { name=$1; shift; wb=$1; shift
  (cd "$VI" && env "$@" TB_STREAM="$ST/$name.bin" ./obj_vi/tb_vi 1 0 30 "$wb" > "$ST/$name.log" 2>&1) || echo "  (tb_vi: $ST/$name.log)"
  echo "== $name ($*, WB $wb)"
  for m in 0 1 2 3 4; do for d in 0 1; do "$PF" replay "$ST/$name.bin" $m $d || rc=1; done; done; }
run libultra237_crop8_1 320 TB_PX0=0 TB_PW=640 TB_Y0=0 TB_ROWS=237 TB_CROPV=8 TB_CROPR=1     # libultra's NTSC window at the core's defaults: 638 x 221
run libultra237_nocrop 320 TB_PX0=0 TB_PW=640 TB_Y0=0 TB_ROWS=237 TB_CROPV=0 TB_CROPR=0
run win240_crop8_1 320 TB_PX0=0 TB_PW=640 TB_Y0=0 TB_ROWS=240 TB_CROPV=8 TB_CROPR=1         # (Donkey Kong 64: 638 x 224)
run libultra237_crop4 320 TB_ROWS=237 TB_CROPV=4 TB_CROPR=1
run libultra237_crop12 320 TB_ROWS=237 TB_CROPV=12 TB_CROPR=1
run win384 384 TB_CROPV=8 TB_CROPR=1
run short225_y6 320 TB_Y0=6 TB_ROWS=225 TB_CROPV=8 TB_CROPR=1
run pal240 320 TB_PAL=1 TB_ROWS=240 TB_CROPV=8 TB_CROPR=1
run hires_640p 640p TB_CROPV=8 TB_CROPR=1
run woven 640s TB_CROPV=8 TB_CROPR=1
rm -rf "$ST"; exit $rc

#!/bin/sh
# Requires Verilator with --binary/--timing support and a C++ compiler.
set -eu
R=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
B=$(mktemp -d)
trap 'rm -rf "$B"' EXIT HUP INT TERM
"${VERILATOR:-verilator}" --binary --timing --top-module fps_test -Wno-fatal -Wno-PINMISSING \
    -I"$R/rtl/soc" --Mdir "$B/obj" "$R/rtl/soc/n64_video.sv" "$R/rtl/soc/afifo.sv" \
    "$R/rtl/soc/mirlo_regs.sv" "$R/sim/fps/fps_test.sv" > "$B/build.log" 2>&1 || {
    cat "$B/build.log"; exit 1;
}
# Keep captures in the caller's directory for inspection.
"$B/obj/Vfps_test"

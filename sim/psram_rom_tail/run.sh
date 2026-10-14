#!/bin/sh
# The ROM tail in PSRAM die 1 (rtl/soc/psram_rom_tail.sv) under Verilator (--binary --timing): tb_psram_rom_tail.sv.
# Mutants of the controller's timing (a read taken early, a write pulse too short) must fail.
set -u
R=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
H="$R/sim/psram_rom_tail"
VL="${VERILATOR:-verilator}"
B=$(mktemp -d)
trap 'rm -rf "$B"' EXIT HUP INT TERM
build() {   # name, extra args
    "$VL" --binary --timing -j 4 -Wno-fatal -Wno-lint -Wno-style -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Mdir "$B/$1" --top-module tb_psram_rom_tail \
        $2 "$R/rtl/soc/psram_rom_tail.sv" "$R/rtl/soc/n64_ports.sv" "$R/rtl/soc/rcp_mi.sv" "$H/tb_psram_rom_tail.sv" -o tb > "$B/$1.log" 2>&1 \
        || { grep -A3 "%Error" "$B/$1.log" | head -20; return 1; }
    "$B/$1/tb" 2>&1 | grep -a "tb_psram_rom_tail"
}
echo "== reference"
build ref "" > "$B/ref.out"
tail -5 "$B/ref.out"
grep -q "PASS" "$B/ref.out" || exit 1
for m in "-GT_RD=5" "-GT_WR=2"; do
    echo "== mutant $m: must fail"
    build mut "$m" > "$B/mut.out"
    if grep -q "FAIL\|violation\|pulse\|contention" "$B/mut.out"; then echo "failed, as it must"; else echo "MUTANT SURVIVED"; exit 1; fi
    rm -rf "$B/mut"
done
echo "psram_rom_tail: PASS"

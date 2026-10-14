#!/bin/sh
# The ROM tail in PSRAM die 1 (rtl/soc/psram_rom_tail.sv + the X port of target/pocket/pocket_video_psram.sv) under Verilator
# (--binary --timing): tb_psram_rom_tail.sv, with the display's traffic on die 0 alongside.
# Mutants must fail: a read taken early, a short write pulse, the X port always first (the display starved).
set -u
R=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
H="$R/sim/psram_rom_tail"
VL="${VERILATOR:-verilator}"
B=$(mktemp -d)
trap 'rm -rf "$B"' EXIT HUP INT TERM
CTL="$R/target/pocket/pocket_video_psram.sv"
build() {   # name, extra args, the controller's file
    "$VL" --binary --timing -j 4 -Wno-fatal -Wno-lint -Wno-style -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Mdir "$B/$1" --top-module tb_psram_rom_tail \
        $2 "$3" "$R/rtl/soc/psram_rom_tail.sv" "$R/rtl/soc/n64_ports.sv" "$R/rtl/soc/rcp_mi.sv" "$H/tb_psram_rom_tail.sv" -o tb > "$B/$1.log" 2>&1 \
        || { grep -A3 "%Error" "$B/$1.log" | head -20; return 1; }
    "$B/$1/tb" 2>&1 | grep -a "tb_psram_rom_tail"
}
echo "== reference"
build ref "" "$CTL" > "$B/ref.out"
cat "$B/ref.out"
grep -q "PASS" "$B/ref.out" || exit 1
mutant() {  # name, args, controller file, what
    echo "== mutant $1 ($4): must fail"
    build "mut_$1" "$2" "$3" > "$B/mut.out"
    if grep -q "FAIL" "$B/mut.out"; then echo "failed, as it must"; else echo "MUTANT SURVIVED"; exit 1; fi
    rm -rf "$B/mut_$1"
}
mutant rd "-GT_RD=5" "$CTL" "an X read taken 2 cycles early"
sed "s/if (a_wr \&\& t == 15'd5) begin o_we_n/if (a_wr \&\& t == 15'd2) begin o_we_n/" "$CTL" > "$B/short.sv"
cmp -s "$B/short.sv" "$CTL" && { echo "mutant short: matched nothing"; exit 1; }
mutant short "" "$B/short.sv" "WE# low for 1 cycle"
sed "s/(!z_valid || x_turn)/1'b1/" "$CTL" > "$B/first.sv"
cmp -s "$B/first.sv" "$CTL" && { echo "mutant first: matched nothing"; exit 1; }
mutant first "" "$B/first.sv" "the X port always first: the display starves"
echo "psram_rom_tail: PASS"

#!/bin/sh
# The Pocket's read-modify-write cycle on the core's settings against the real register file (Icarus), over spacings and orders.
#   sh sim/interact_bridge/run.sh            the sweep; MIN=<cycles> is the smallest spacing that must pass (default 40)
set -eu
R=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
H=$R/sim/interact_bridge
B=$(mktemp -d)
trap 'rm -rf "$B"' EXIT HUP INT TERM
python3 "$H/gen_elements.py" "$R/pkg/pocket/Cores/tortuga.Mirlo64/interact.json" > "$B/elements.svh"
fail=0
for order in 0 1; do
 for mode in 0 1; do
  for s in ${SPACINGS:-6 10 16 24 32 40 60 100}; do
    iverilog -g2012 -I "$R/rtl/soc" -I "$B" -P interact_bridge_test.S=$s -P interact_bridge_test.MODE=$mode -P interact_bridge_test.ORDER=$order -s interact_bridge_test -o "$B/sim" \
        "$R/rtl/soc/mirlo_regs.sv" "$R/rtl/soc/fifo_fwft.sv" "$R/sim/interact/rcp_mi_stub.sv" "$R/target/pocket/sync_fifo.sv" \
        "$H/dcfifo_model.sv" "$H/interact_bridge_test.sv" 2>&1 | grep -E 'error|Error' || true
    out=$(vvp -N "$B/sim" | grep -v 'sorry\|finish')
    echo "$out" | grep 'interact_bridge'
    echo "$out" | grep -v 'interact_bridge S=' || true
    # (the shuffled order, ORDER=1, is a stress that shows a hazard of the template's read path: reported, not gated)
    if [ "$order" = 0 ] && [ "$s" -ge "${MIN:-40}" ] && ! echo "$out" | grep -q 'PASS'; then fail=1; fi
  done
 done
done
[ $fail = 0 ] && echo "interact_bridge: PASS (spacings of ${MIN:-40} and more)" || { echo "interact_bridge: FAIL"; exit 1; }

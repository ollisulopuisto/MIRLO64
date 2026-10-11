#!/bin/bash
# fullpath.sh <projects dir> [paths]: the full report of the worst setup paths of a finished fit, one per endpoint (every cell and
# wire with its delay, the clock's skew): where the margin goes. Slow 85C model, the corner that fails.
d=$1; n=${2:-6}
cd $d && cat > /tmp/a2_fp_$$.tcl <<TCL
project_open mirlo
create_timing_netlist -model slow
read_sdc
update_timing_netlist
report_timing -setup -npaths $n -nworst 1 -detail full_path -file /tmp/a2_fp_$$.txt
project_close
TCL
${QUARTUS_BIN:-$HOME/altera/25.1std/quartus/bin}/quartus_sta -t /tmp/a2_fp_$$.tcl >/dev/null 2>&1
cat /tmp/a2_fp_$$.txt
rm -f /tmp/a2_fp_$$.*

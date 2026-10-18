#!/bin/sh
# Screen Size (target/pocket/pocket_frame.sv) against a model of what it should send. Requires Verilator, a C++ compiler
# and make; VERILATOR overrides the executable.
set -eu
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
"${VERILATOR:-verilator}" --cc --exe --build -j 4 --top-module pocket_frame \
    --Mdir "$HERE/obj_dir" "$HERE/../../target/pocket/pocket_frame.sv" "$HERE/tb_pocket_frame.cpp" -o tb_pocket_frame
"$HERE/obj_dir/tb_pocket_frame"

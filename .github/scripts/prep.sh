#!/bin/bash
# Host-side build steps from the README (steps 1-4). Run from the repo root.
set -euxo pipefail
export MIPS_CC=mips-linux-gnu-gcc MIPS_BIN=mips-linux-gnu-
make -C lang/mips -f lib.mk VARIANT=game
make -C lang/mips/boot
python3 sim/rsp/make_div_rom.py rtl/rsp/rsp_div_rom.hex
python3 tools/mips_inits.py

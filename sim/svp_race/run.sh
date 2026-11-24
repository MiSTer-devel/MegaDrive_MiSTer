#!/bin/sh
# Directed test of the SVP status race (tb_svp_race.vhd), GHDL.  Optional argument: the SVP.vhd to test
# (default ../../rtl/SVP/SVP.vhd).  Exit status 0 when every start offset sees SA.
set -e
D=$(cd "$(dirname "$0")" && pwd)
R="$D/../../rtl/SVP"
SVP=${1:-$R/SVP.vhd}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
F="--std=08 -fsynopsys --workdir=$W"
ghdl -a $F "$D/sim_ram.vhd" "$R/SSP160x_PKG.vhd" "$R/SSP160x.vhd" "$SVP" "$D/tb_svp_race.vhd"
ghdl -e $F -o "$W/tb_svp_race" tb_svp_race
"$W/tb_svp_race" --assert-level=failure --ieee-asserts=disable-at-0

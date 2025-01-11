# Copyright 2022 Flavien Solt, ETH Zurich.
# Licensed under the General Public License, Version 3.0, see LICENSE for details.
# SPDX-License-Identifier: GPL-3.0-only

set -e
export SIMLEN=10000
export TRACEFILE=$PWD/out.trace
. ../../../cellift-meta/env.sh
benchmarks=$CELLIFT_META_ROOT/benchmarks/out/ibex/bin/
( cd $CELLIFT_META_ROOT/benchmarks && bash build-benchmarks.sh ibex )
bin=$benchmarks/median.riscv
export SIMROMELF=$bin
export SIMSRAMELF=$bin
if [ ! -f $bin ]
then
    echo Benchmarks failed to build.
    exit 1
fi
make run_vanilla_trace
make run_vanilla_trace_fst
make run_vanilla_notrace
make run_passthrough_trace
make run_passthrough_trace_fst
make run_passthrough_notrace
make run_cellift_trace
make run_cellift_trace_fst
make run_cellift_notrace

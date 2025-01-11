# Copyright 2022 Flavien Solt, ETH Zurich.
# Licensed under the General Public License, Version 3.0, see LICENSE for details.
# SPDX-License-Identifier: GPL-3.0-only

import os
import multiprocessing as mp
import subprocess
import itertools
from pathlib import Path

SCATTER_DIR = "generated/scattered"
SV_SRCS_DIR = "generated/sv_sources"
NUM_PROCESSES = mp.cpu_count()//2

SRCS_TO_SKIP = {
    "ibex_tracer.sv",
    "ibex_register_file_latch.sv",
    "ibex_register_file_fpga.sv",
    "ibex_top_tracing.sv",
    "prim_xilinx_pad_wrapper.sv",
    "prim_generic_pad_wrapper.sv",
    "prim_assert.sv",
    "pins_if.sv",
}

SV2V_BASE_CMD = r"sv2v --define=SYNTHESIS --exclude=Always generated/sv_sources/*_pkg.sv ../vendor/lowrisc_ip/ip/prim/rtl/prim_ram_1p_pkg.sv -I ../vendor/lowrisc_ip/ip/prim/rtl -I ../vendor/lowrisc_ip/dv/sv/dv_utils"
SV2V_CLK_GATING_CMD = r"sv2v --define=SYNTHESIS --exclude=Always"

def apply_base_sv2v(filepath):
    filename = os.path.basename(filepath)
    print("applying sv2v:", filename)
    source_filename = os.path.join(SV_SRCS_DIR,filename)
    target_filename = os.path.join(SCATTER_DIR,filename[:-3]+".v")
    sv2v_command = "{} {} -w {}".format(SV2V_BASE_CMD, source_filename, target_filename)
    subprocess.run(sv2v_command, shell=True)
    # sv2v does not add a newline, so let's do apparently.
    with open(target_filename, 'a') as outfile:
        outfile.write('\n')

if __name__ == "__main__":
    # Create the target directory.
    Path(SCATTER_DIR).mkdir(parents=True, exist_ok = True)

    # Load and filter the sources.
    # (a) exclude the irrelevant modules.
    src_list = filter(lambda filename: filename not in SRCS_TO_SKIP, os.listdir(SV_SRCS_DIR))
    # (b) only sv files.
    src_list = filter(lambda src_name: src_name[-3:] == ".sv", src_list)
    # (c) remove packages.
    src_list = filter(lambda src_name: "_pkg" not in src_name, src_list)
    # (d) add directory to the path.
    src_list = map(lambda filename: os.path.join(SV_SRCS_DIR, filename), src_list)
    # (e) also add our toplevel.
    src_list = itertools.chain(src_list, ["../syn/rtl/rv_core_ibex_mem_top.sv"])

    # Parallelize the sv2v application on the sv2v sources.
    pool = mp.Pool(NUM_PROCESSES)
    pool.map(apply_base_sv2v, src_list)
    pool.close()
    pool.join()

    # Finish some isolated workload.
    src = "../syn/rtl/prim_clock_gating"
    target_filename = os.path.join(SCATTER_DIR, "prim_clock_gating.v")
    sv2v_command = "{} {}.v -w {}".format(SV2V_CLK_GATING_CMD, src, target_filename)
    subprocess.run(sv2v_command, shell=True)
    # sv2v does not add a newline, so let's do apparently.
    with open(target_filename, 'a') as outfile:
        outfile.write('\n')

else:
    raise Exception("Module gen_sv2v_out must be a toplevel module.")

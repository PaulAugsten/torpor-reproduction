#!/bin/bash
# Table 4, Swap-NVLink column (Apptainer port of run_figure4_swap_NVLink.sh).
# Usage: ./run_table4_swap_nvlink.sh   (compute node, venv active)
cd "$(dirname "$0")"
source ../common/env.sh
COLUMN="swap_nvlink"
DRIVER="swap_NVLink_latency.py"
SERVER_SIF="${SERVER_SIF:-$TORPOR/images/torpor-server-nvlink.sif}"
source ../common/model_loop.sh

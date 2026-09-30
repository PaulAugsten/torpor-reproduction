#!/bin/bash
# Table 4, Swap-PCIe column (Apptainer port of run_figure4_swap_PCIe.sh).
# Usage: ./run_table4_swap_pcie.sh   (compute node, venv active)
cd "$(dirname "$0")"
source ../common/env.sh
COLUMN="swap_pcie"
DRIVER="swap_PCIe_latency.py"
SERVER_SIF="${SERVER_SIF:-$TORPOR/images/torpor-server.sif}"
source ../common/model_loop.sh

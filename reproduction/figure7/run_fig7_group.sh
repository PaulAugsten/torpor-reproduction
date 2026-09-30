#!/bin/bash
# Figure 7, +Group: default server build and buffer settings (full Torpor).
# Usage: ./run_fig7_group.sh   (compute node, venv active)
cd "$(dirname "$0")"
source ../common/env.sh
COLUMN="fig7_group"
DRIVER="swap_PCIe_latency.py"
MODELS=(bertqa resnet152)
SERVER_SIF="${SERVER_SIF:-$TORPOR/images/torpor-server.sif}"
source ../common/model_loop.sh

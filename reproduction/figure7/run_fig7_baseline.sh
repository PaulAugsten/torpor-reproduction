#!/bin/bash
# Figure 7, Baseline: server built with the pinned staging path in
# memory_manager.hpp commented out (upstream Figure 7 README; prebuilt as
# torpor-server-fig7-baseline.sif, see ../images/).
# Usage: ./run_fig7_baseline.sh   (compute node, venv active)
cd "$(dirname "$0")"
source ../common/env.sh
COLUMN="fig7_baseline"
DRIVER="swap_PCIe_latency.py"
MODELS=(bertqa resnet152)
EXTRA_SERVER_ENV=",BUFFER_SIZE=1610612736"
SERVER_SIF="${SERVER_SIF:-$TORPOR/images/torpor-server-fig7-baseline.sif}"
source ../common/model_loop.sh

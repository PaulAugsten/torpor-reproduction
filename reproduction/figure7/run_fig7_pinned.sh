#!/bin/bash
# Figure 7, +Pinned: BUFFER_SIZE=1610612736 (1.5 GB, i.e. no pipelining),
# per the upstream Figure 7 README.
# Usage: ./run_fig7_pinned.sh   (compute node, venv active)
cd "$(dirname "$0")"
source ../common/env.sh
COLUMN="fig7_pinned"
DRIVER="swap_PCIe_latency.py"
MODELS=(bertqa resnet152)
EXTRA_SERVER_ENV=",BUFFER_SIZE=1610612736"
SERVER_SIF="${SERVER_SIF:-$TORPOR/images/torpor-server.sif}"
source ../common/model_loop.sh

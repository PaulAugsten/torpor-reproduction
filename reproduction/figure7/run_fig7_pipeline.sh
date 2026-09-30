#!/bin/bash
# Figure 7, +Pipeline: BUFFER_SIZE=1, i.e. per-parameter pipelining without
# grouping, per the upstream Figure 7 README.
# Usage: ./run_fig7_pipeline.sh   (compute node, venv active)
cd "$(dirname "$0")"
source ../common/env.sh
COLUMN="fig7_pipeline"
DRIVER="swap_PCIe_latency.py"
MODELS=(bertqa resnet152)
EXTRA_SERVER_ENV=",BUFFER_SIZE=1"
SERVER_SIF="${SERVER_SIF:-$TORPOR/images/torpor-server.sif}"
source ../common/model_loop.sh

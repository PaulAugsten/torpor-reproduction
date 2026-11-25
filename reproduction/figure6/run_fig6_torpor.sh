#!/bin/bash
# Figure 6, Torpor bar (default build, CUDA-call batching enabled).
# Usage: ./run_fig6_torpor.sh   (compute node, venv active)
cd "$(dirname "$0")"
source ../common/env.sh
COLUMN="fig6_torpor"
DRIVER="fig6_torpor.py"
MODELS=(bertqa resnet152)
SERVER_SIF="${SERVER_SIF:-$TORPOR/images/torpor-server.sif}"
source ../common/model_loop.sh

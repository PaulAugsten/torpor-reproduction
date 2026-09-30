#!/bin/bash
# Table 4, GPU remoting column (Apptainer port of run_figure4_GPU_remoting.sh).
# Usage: ./run_table4_remoting.sh   (compute node, venv active)
cd "$(dirname "$0")"
source ../common/env.sh
COLUMN="remoting"
DRIVER="GPU_remoting_latency.py"
SERVER_SIF="${SERVER_SIF:-$TORPOR/images/torpor-server.sif}"
source ../common/model_loop.sh

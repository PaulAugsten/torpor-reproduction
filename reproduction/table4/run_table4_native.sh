#!/bin/bash
# Table 4, Native column: all 8 models in one container, no Torpor server.
# Model weights come from the offline caches in $TORPOR/models.
# Usage: ./run_table4_native.sh   (compute node)
cd "$(dirname "$0")"
source ../common/env.sh
apptainer exec --nv \
    --env TORCH_HOME=$TORPOR/models/torch,HF_HOME=$TORPOR/models/hf,HF_HUB_OFFLINE=1,TRANSFORMERS_OFFLINE=1 \
    "$TORPOR/images/torpor-native.sif" \
    python3 run_figure4_native.py | tee results_native.txt

#!/bin/bash
# Sourced by every run_* and sbatch_* script. Expected layout:
#   $TORPOR/torpor   this repository
#   $TORPOR/images   Apptainer images (see ../images/README.md)
#   $TORPOR/models   offline model caches, used as TORCH_HOME and HF_HOME
#   $TORPOR/venv     Python environment for the host-side drivers
# Export TORPOR beforehand to use a different location.
if [ -z "${TORPOR:-}" ]; then
    TORPOR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fi
export TORPOR

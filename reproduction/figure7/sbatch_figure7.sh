#!/bin/bash
#SBATCH --job-name=figure7-repro
#SBATCH --partition=dc-gpu
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --gres=gpu:4,mem512:1
#SBATCH --time=04:00:00
#SBATCH --output=logs_batch/slurm-%j.out
#SBATCH --error=logs_batch/slurm-%j.err
#
# Full Figure 7 run (Baseline, +Group, +Pipeline, +Pinned; resnet152 and bertqa).
# Submit from this directory:
#   mkdir -p logs_batch && sbatch -A <project> sbatch_figure7.sh

set -u
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"
mkdir -p logs_batch
source ../common/env.sh

source "$TORPOR/venv/bin/activate"

RESULTS_DIR="${RESULTS_ROOT:-$HOME/results}/figure_7"
mkdir -p "$RESULTS_DIR"

echo "=================================================="
echo "Figure 7 reproduction starting at $(date)"
echo "=================================================="

./run_all_figure7.sh
RC=$?
if [ "$RC" -ne 0 ]; then
    echo "WARNING: run_all_figure7.sh exited with code $RC -- saving whatever results it produced"
fi

if compgen -G "results_*.txt" > /dev/null; then
    cp results_*.txt "$RESULTS_DIR/"
else
    echo "WARNING: no result files found"
fi

echo "=================================================="
echo "Figure 7 done at $(date)"
if [ "$RC" -ne 0 ]; then
    echo "At least one variant failed -- check logs_batch/slurm-${SLURM_JOB_ID}.out and logs_*/ for details."
else
    echo "All variants completed successfully."
fi
echo "Results saved to: $RESULTS_DIR (raw logs kept in logs_*/)"

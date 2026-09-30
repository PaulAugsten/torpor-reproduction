#!/bin/bash
#SBATCH --job-name=figure6-repro
#SBATCH --partition=dc-gpu
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --gres=gpu:4,mem512:1
#SBATCH --time=03:00:00
#SBATCH --output=logs_batch/slurm-%j.out
#SBATCH --error=logs_batch/slurm-%j.err
#
# Full Figure 6 run (Torpor vs. w/o batch; resnet152 and bertqa).
# Submit from this directory:
#   mkdir -p logs_batch && sbatch -A <project> sbatch_figure6.sh

set -u
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"
mkdir -p logs_batch
source ../common/env.sh

source "$TORPOR/venv/bin/activate"

RESULTS_DIR="${RESULTS_ROOT:-$HOME/results}/figure_6"
mkdir -p "$RESULTS_DIR"

echo "=================================================="
echo "Figure 6 reproduction starting at $(date)"
echo "=================================================="

./run_all_figure6.sh
RC=$?
if [ "$RC" -ne 0 ]; then
    echo "WARNING: run_all_figure6.sh exited with code $RC -- saving whatever results it produced"
fi

if compgen -G "results_*.txt" > /dev/null; then
    cp results_*.txt "$RESULTS_DIR/"
else
    echo "WARNING: no result files found"
fi

echo "=================================================="
echo "Figure 6 done at $(date)"
if [ "$RC" -ne 0 ]; then
    echo "At least one step failed -- check logs_batch/slurm-${SLURM_JOB_ID}.out and logs_*/ for details."
else
    echo "All runs completed successfully."
fi
echo "Results saved to: $RESULTS_DIR (raw logs kept in logs_*/)"

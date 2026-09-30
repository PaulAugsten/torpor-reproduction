#!/bin/bash
#SBATCH --job-name=figure8-repro
#SBATCH --partition=dc-gpu
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --gres=gpu:4,mem512:1
#SBATCH --time=10:00:00
#SBATCH --output=logs_batch/slurm-%j.out
#SBATCH --error=logs_batch/slurm-%j.err
#
# Full Figure 8 run (Native at 19 functions x 80/60/40/20/10 rpm, Torpor at
# (33,80) (40,60) (60,40) (120,20) (210,10)). The experiment uses GPU 0 only,
# but the whole node is requested so that nothing else runs on it.
# Submit from this directory:
#   mkdir -p logs_batch && sbatch -A <project> sbatch_figure8.sh

set -u
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"
mkdir -p logs_batch
source ../common/env.sh

source "$TORPOR/venv/bin/activate"

RESULTS_DIR="${RESULTS_ROOT:-$HOME/results}/figure_8"
mkdir -p "$RESULTS_DIR"

echo "=================================================="
echo "Figure 8 reproduction starting at $(date)"
echo "=================================================="

./run_all_figure8.sh
RC=$?
if [ "$RC" -ne 0 ]; then
    echo "WARNING: run_all_figure8.sh exited with code $RC -- saving whatever results it produced"
fi

if compgen -G "logs_fig8/*_result.txt" > /dev/null; then
    cp logs_fig8/*_result.txt "$RESULTS_DIR/"
else
    echo "WARNING: no result files found"
fi

echo "=================================================="
echo "Figure 8 done at $(date)"
if [ "$RC" -ne 0 ]; then
    echo "At least one step failed -- check logs_batch/slurm-${SLURM_JOB_ID}.out and logs_fig8/ for details."
else
    echo "All runs completed successfully."
fi
echo "Results saved to: $RESULTS_DIR (raw logs kept in logs_fig8/)"

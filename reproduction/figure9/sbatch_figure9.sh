#!/bin/bash
#SBATCH --job-name=figure9-repro
#SBATCH --partition=dc-gpu
#SBATCH --qos=normal
#SBATCH --nodes=1
#SBATCH --gres=gpu:4,mem512:1
#SBATCH --time=06:00:00
#SBATCH --output=logs_batch/slurm-%j.out
#SBATCH --error=logs_batch/slurm-%j.err
#
# Full Figure 9 run (Native and Torpor, 40 resnet152 functions on 4 GPUs,
# four random traces each).
# Submit from this directory:
#   mkdir -p logs_batch && sbatch -A <project> sbatch_figure9.sh

set -u
cd "${SLURM_SUBMIT_DIR:-$(dirname "$0")}"
mkdir -p logs_batch
source ../common/env.sh

ulimit -c 0

source "$TORPOR/venv/bin/activate"

RESULTS_DIR="${RESULTS_ROOT:-$HOME/results}/figure_9"
mkdir -p "$RESULTS_DIR"

echo "=================================================="
echo "Figure 9 reproduction starting at $(date)"
echo "=================================================="

./run_all_figure9.sh
RC=$?
if [ "$RC" -ne 0 ]; then
    echo "WARNING: run_all_figure9.sh exited with code $RC -- saving whatever results it produced"
fi

if compgen -G "logs_fig9/*_result.txt" > /dev/null; then
    # Keep only one job's results at the top level, so Native and Torpor rows
    # from different jobs are never mixed. Older results move to previous/.
    if compgen -G "$RESULTS_DIR/*_result.txt" > /dev/null; then
        mkdir -p "$RESULTS_DIR/previous"
        mv "$RESULTS_DIR"/*_result.txt "$RESULTS_DIR/previous/"
        [ -f "$RESULTS_DIR/JOB" ] && mv "$RESULTS_DIR/JOB" "$RESULTS_DIR/previous/JOB"
    fi
    cp logs_fig9/*_result.txt "$RESULTS_DIR/"
    echo "job ${SLURM_JOB_ID} on $(hostname), finished $(date -Is)" > "$RESULTS_DIR/JOB"
else
    echo "WARNING: no result files found"
fi

echo "=================================================="
echo "Figure 9 done at $(date)"
if [ "$RC" -ne 0 ]; then
    echo "At least one step failed -- check logs_batch/slurm-${SLURM_JOB_ID}.out and logs_fig9/ for details."
else
    echo "All runs completed successfully."
fi
echo "Results saved to: $RESULTS_DIR (raw logs kept in logs_fig9/)"
